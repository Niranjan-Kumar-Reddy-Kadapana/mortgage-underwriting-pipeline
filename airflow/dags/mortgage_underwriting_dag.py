"""Mortgage underwriting pipeline.

  generate (demo only) -> [load applications, load credit bureau] -> source freshness
      -> dbt build silver -> dbt build gold -> dbt docs

Both loads must succeed before Silver runs (default all_success trigger rule).
dbt build runs models AND their tests/unit tests, and skips downstream nodes if a test fails.
Any task failure triggers alerts.notify_failure.
"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

sys.path.insert(0, os.path.dirname(__file__))
from alerts import notify_failure  # noqa: E402

PROJECT = os.getenv("PROJECT_DIR", "/opt/airflow/project")
DBT = os.getenv("DBT_BIN", "dbt")
TARGET = os.getenv("DBT_TARGET", "prod")
DATA_DIR = f"{PROJECT}/data/out"
DBT_CMD = f"cd {PROJECT}/dbt && {DBT} %s --target {TARGET} --profiles-dir ."


def _load(source: str):
    sys.path.insert(0, PROJECT)
    from ingestion.load_bronze import run
    run(source, DATA_DIR)


default_args = {
    "owner": "data-engineering",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email": [os.getenv("ALERT_EMAIL", "data-alerts@example.com")],
    "email_on_failure": True,
    "on_failure_callback": notify_failure,
}

with DAG(
    dag_id="mortgage_underwriting",
    description="Bronze -> Silver -> Gold underwriting pipeline",
    default_args=default_args,
    start_date=datetime(2026, 1, 1),
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    tags=["mortgage", "dbt", "snowflake"],
) as dag:
    generate = BashOperator(
        task_id="generate_sample_data",   # demo only; in production files arrive from source systems
        bash_command=(f"python {PROJECT}/data_simulation/generate_data.py --out {DATA_DIR} "
                      "--rows 5000 --batch {{ ds_nodash }} --seed {{ ds_nodash }}"),
    )
    load_apps = PythonOperator(task_id="load_applications", python_callable=_load, op_args=["applications"])
    load_credit = PythonOperator(task_id="load_credit_bureau", python_callable=_load, op_args=["credit"])
    freshness = BashOperator(task_id="dbt_source_freshness", bash_command=DBT_CMD % "source freshness")
    silver = BashOperator(task_id="dbt_build_silver", bash_command=DBT_CMD % "build --select tag:silver --exclude tag:gold")
    gold = BashOperator(task_id="dbt_build_gold", bash_command=DBT_CMD % "build --select tag:gold")
    docs = BashOperator(task_id="dbt_docs_generate", bash_command=DBT_CMD % "docs generate",
                        trigger_rule="all_done")

    generate >> [load_apps, load_credit] >> freshness >> silver >> gold >> docs
