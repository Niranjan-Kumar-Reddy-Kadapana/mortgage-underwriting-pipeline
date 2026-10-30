FROM apache/airflow:2.10.5-python3.11
# dbt lives in its own venv so its dependency pins never fight Airflow's.
RUN python -m venv /opt/dbt-venv && /opt/dbt-venv/bin/pip install --no-cache-dir "dbt-snowflake>=1.8,<2.0"
RUN pip install --no-cache-dir snowflake-connector-python
ENV DBT_BIN=/opt/dbt-venv/bin/dbt PROJECT_DIR=/opt/airflow/project
