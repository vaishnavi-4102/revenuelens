"""RevenueLens :: 30_dbt_marts_and_tests

Builds intermediate + marts_finance and runs the full test suite --
"publish/validate" in the architecture doc's ingestion -> transform ->
publish/validate framing. `dbt test` includes the singular reconciliation
tests (tests/reconciliation/*.sql); a failure here means the ARR waterfall
or revenue reconciliation stopped holding mathematically, which is a
release blocker, not a warning.

fct_revenue_reconciliation_monthly and rpt_restatement_log are incremental
with a late-arrival lookback (dbt/dbt_project.yml `vars.reprocess_lookback_days`).
`--vars '{"run_date": ...}'` passes this DAG's logical date through to that
lookback window (see dbt/macros/as_of.sql) -- without it, every run
(including a backfill for a past date) would compute "lookback_days back
from right now" instead of "...from the date being processed", which
defeats the point of backfilling a historical month at all.
"""
from datetime import datetime
from pathlib import Path

from airflow import DAG
from airflow.datasets import Dataset
from airflow.models import Variable
from airflow.operators.bash import BashOperator

# airflow/dags/<this file> -> repo root is two levels up. Computed from this
# file's own location rather than a hardcoded string, so it's correct
# whether the repo lives on a laptop at an arbitrary path or is bind-mounted
# into a container at an arbitrary path -- the Airflow Variable can still
# override it if a deployment ever needs to.
_REPO_ROOT_DEFAULT = str(Path(__file__).resolve().parents[2])
PROJECT_DIR = Variable.get("revenuelens_project_dir", default_var=_REPO_ROOT_DEFAULT)

stg_dataset = Dataset("snowflake://staging/all")

default_args = {
    "owner": "analytics_engineering",
    "depends_on_past": False,
    "start_date": datetime(2024, 1, 1),
    "retries": 0,
}

DBT_VARS = '{"run_date": "{{ ds }}"}'

with DAG(
    "30_dbt_marts_and_tests",
    default_args=default_args,
    schedule=[stg_dataset],
    catchup=False,
    tags=["revenuelens", "dbt", "publish"],
) as dag:

    dbt_marts = BashOperator(
        task_id="dbt_run_marts",
        # --target prod: same reasoning as 20_dbt_staging.py -- must match
        # 10_ingestion's load target or this builds against the wrong
        # (empty/stale) database entirely.
        bash_command=(
            f"cd {PROJECT_DIR}/dbt && "
            f"dbt run --select intermediate marts --target prod --vars '{DBT_VARS}'"
        ),
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"cd {PROJECT_DIR}/dbt && "
            f"dbt test --target prod --vars '{DBT_VARS}'"
        ),
    )

    dbt_marts >> dbt_test
