"""RevenueLens :: 30_dbt_marts_and_tests

Builds intermediate + marts_finance and runs the full test suite --
"publish/validate" in the architecture doc's ingestion -> transform ->
publish/validate framing. `dbt test` includes the singular reconciliation
tests (tests/reconciliation/*.sql); a failure here means the ARR waterfall
or revenue reconciliation stopped holding mathematically, which is a
release blocker, not a warning.

fct_revenue_reconciliation_monthly is materialized incremental with a
late-arrival lookback (see dbt/dbt_project.yml `vars.reprocess_lookback_days`)
-- a plain `dbt run` here already reprocesses just the affected months when
a late credit memo lands, no separate DAG needed for that.
"""
from datetime import datetime

from airflow import DAG
from airflow.datasets import Dataset
from airflow.models import Variable
from airflow.operators.bash import BashOperator

PROJECT_DIR = Variable.get("revenuelens_project_dir", default_var="/home/sigmoid/Revenuelense/revenuelens")

stg_dataset = Dataset("snowflake://staging/all")

default_args = {
    "owner": "analytics_engineering",
    "depends_on_past": False,
    "start_date": datetime(2024, 1, 1),
    "retries": 0,
}

with DAG(
    "30_dbt_marts_and_tests",
    default_args=default_args,
    schedule=[stg_dataset],
    catchup=False,
    tags=["revenuelens", "dbt", "publish"],
) as dag:

    dbt_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=f"cd {PROJECT_DIR}/dbt && dbt run --select intermediate marts",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {PROJECT_DIR}/dbt && dbt test",
    )

    dbt_marts >> dbt_test
