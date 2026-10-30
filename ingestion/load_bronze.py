"""Load local files into Snowflake Bronze (PUT to internal stage, then COPY INTO).

Idempotent: COPY INTO remembers loaded file names for 64 days, so re-running a failed
Airflow task never double-loads. In production replace this with Snowpipe auto-ingest.
"""
from __future__ import annotations

import argparse
import glob
import os
from pathlib import Path

import snowflake.connector


def connect():
    cfg = dict(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        role=os.getenv("SNOWFLAKE_LOADER_ROLE", "MORTGAGE_LOADER_ROLE"),
        warehouse=os.getenv("SNOWFLAKE_LOADING_WH", "MORTGAGE_LOADING_WH"),
        database=os.getenv("SNOWFLAKE_DATABASE", "MORTGAGE_DEV"),
        schema="BRONZE",
    )
    if os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH"):
        cfg["private_key_file"] = os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]
    else:
        cfg["password"] = os.environ["SNOWFLAKE_PASSWORD"]
    return snowflake.connector.connect(**cfg)


def init_objects(cur):
    sql = (Path(__file__).resolve().parents[1] / "snowflake" / "01_bronze_objects.sql").read_text()
    for stmt in (s.strip() for s in sql.split(";")):
        body = "\n".join(l for l in stmt.splitlines() if not l.strip().startswith("--")).strip()
        if body:
            cur.execute(body)


def _put(cur, pattern: str, stage_path: str) -> int:
    files = sorted(glob.glob(pattern))
    for f in files:
        cur.execute(f"PUT 'file://{Path(f).resolve().as_posix()}' @bronze.raw_stage/{stage_path}/ "
                    "AUTO_COMPRESS=TRUE OVERWRITE=FALSE")
    return len(files)


def load_applications(cur, data_dir: str):
    n = _put(cur, f"{data_dir}/applications_*.json", "applications")
    cur.execute("""
        COPY INTO bronze.raw_mortgage_applications (raw, _source_file)
        FROM (SELECT $1, metadata$filename FROM @bronze.raw_stage/applications/)
        FILE_FORMAT = (FORMAT_NAME = 'bronze.ff_json') ON_ERROR = 'ABORT_STATEMENT'""")
    print(f"applications: staged {n} file(s); copy result: {cur.fetchall()}")


def load_credit(cur, data_dir: str):
    n = _put(cur, f"{data_dir}/credit_bureau_*.csv", "credit")
    cur.execute("""
        COPY INTO bronze.raw_credit_bureau
            (applicant_id, ssn, fico_score, monthly_debt, report_date, _source_file)
        FROM (SELECT $1, $2, $3, $4, $5, metadata$filename FROM @bronze.raw_stage/credit/)
        FILE_FORMAT = (FORMAT_NAME = 'bronze.ff_csv') ON_ERROR = 'ABORT_STATEMENT'""")
    print(f"credit bureau: staged {n} file(s); copy result: {cur.fetchall()}")


def run(source: str, data_dir: str, init: bool = False):
    conn = connect()
    try:
        cur = conn.cursor()
        if init:
            init_objects(cur)
        if source in ("applications", "all"):
            load_applications(cur, data_dir)
        if source in ("credit", "all"):
            load_credit(cur, data_dir)
    finally:
        conn.close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", choices=["applications", "credit", "all"], default="all")
    ap.add_argument("--dir", default="data/out")
    ap.add_argument("--init", action="store_true", help="create file formats, stage and Bronze tables first")
    a = ap.parse_args()
    run(a.source, a.dir, a.init)
