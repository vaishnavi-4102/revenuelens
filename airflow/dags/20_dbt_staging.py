"""RevenueLens :: 20_dbt_staging

Builds the staging layer once both the CRM and billing RAW datasets have
been updated by 10_ingestion (data-aware scheduling via Datasets, not cron
chaining -- per the architecture doc).

Renamed from 20_dbt_staging_and_snapshots.py: the dbt `snapshot` step it
used to run is gone on purpose, not an oversight. CRM/customer_master
sources are already an append-only version log (every amendment is a new
row with its own effective_start_date -- see dbt/models/intermediate/
int_contract_versions.sql and int_customer_master_versions.sql), so dbt's
snapshot mechanism has nothing to reconstruct that isn't already in the
data. The two snapshot definitions that used to live here were dead code
(wrong unique_key grain, referenced a column that doesn't exist on
`accounts`) and were removed rather than fixed, since fixing them would
have meant building a mechanism the pipeline doesn't need.
"""
from datetime import datetime
from pathlib import Path

from airflow import DAG
from airflow.datasets import Dataset
from airflow.models import Variable
from airflow.operators.bash import BashOperator

# airflow/dags/<this file> -> repo root is two levels up. Computed from this
# file's own location rather than a hardcoded string -- see 30_dbt_marts_and_tests.py
# for the full rationale.
_REPO_ROOT_DEFAULT = str(Path(__file__).resolve().parents[2])
PROJECT_DIR = Variable.get("revenuelens_project_dir", default_var=_REPO_ROOT_DEFAULT)

raw_billing_dataset = Dataset("snowflake://raw/billing")
raw_crm_dataset = Dataset("snowflake://raw/crm")
stg_dataset = Dataset("snowflake://staging/all")

default_args = {
    "owner": "analytics_engineering",
    "depends_on_past": False,
    "start_date": datetime(2024, 1, 1),
    "retries": 0,
}

with DAG(
    "20_dbt_staging",
    default_args=default_args,
    schedule=[raw_billing_dataset, raw_crm_dataset],
    catchup=False,
    tags=["revenuelens", "dbt"],
) as dag:

    dbt_staging = BashOperator(
        task_id="dbt_staging",
        bash_command=f"cd {PROJECT_DIR}/dbt && dbt run --select staging",
        outlets=[stg_dataset],
    )
