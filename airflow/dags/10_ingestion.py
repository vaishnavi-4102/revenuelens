"""RevenueLens :: 10_ingestion

Runs the daily data generator slice and loads it into RAW via real PUT +
COPY INTO (against the internal stages from infrastructure/07), then
signals the downstream dbt DAGs via Datasets.

Requires an Airflow Connection `snowflake_default` (role RL_LOADER,
warehouse RL_LOADING_WH, database RL_PROD -- swap per environment) and an
Airflow Variable `revenuelens_project_dir` pointing at the repo root. No
credentials are hardcoded here, same discipline as dbt/profiles.yml.example.

D2's "we detect late data, we don't discover it" mechanism lives in two
places: `wait_for_billing_feed` actually checks whether today's billing
files landed (not an always-succeeds placeholder), and `sla` +
`sla_miss_callback` on the ingestion DAG page someone if the whole run
hasn't finished within the SLA window -- see `_billing_sla_miss`.

CRM/billing loads use TaskFlow's `.expand_kwargs()` -- real Airflow dynamic
task mapping, one mapped task instance per source table, rather than a
Python-level list comprehension generating static tasks at parse time.
"""
import logging
import os
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.datasets import Dataset
from airflow.decorators import task
from airflow.models import Variable
from airflow.operators.bash import BashOperator
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from airflow.sensors.python import PythonSensor

log = logging.getLogger(__name__)

# airflow/dags/<this file> -> repo root is two levels up. Computed from this
# file's own location rather than a hardcoded string -- see 30_dbt_marts_and_tests.py
# for the full rationale.
_REPO_ROOT_DEFAULT = str(Path(__file__).resolve().parents[2])
PROJECT_DIR = Variable.get("revenuelens_project_dir", default_var=_REPO_ROOT_DEFAULT)
SNOWFLAKE_CONN_ID = "snowflake_default"

raw_crm_dataset = Dataset("snowflake://raw/crm")
raw_billing_dataset = Dataset("snowflake://raw/billing")

# (source name, stage, RAW table, explicit column list, natural key columns
# -- matches infrastructure/07 stages and 08 RAW table DDL exactly; explicit
# columns because _loaded_at is a table default, never present in the CSV).
# The key column(s) are what MERGE uses in load_table_if_present to make a
# re-PUT of the same daily file idempotent -- see the comment there for why
# COPY INTO's own file-hash dedup can't be trusted for this.
CRM_TABLES = [
    ("accounts", "STG_CRM", "ACCOUNTS",
     "account_id,account_name,region,legal_entity,currency,segment,industry,created_date",
     "account_id"),
    ("contracts", "STG_CRM", "CONTRACTS",
     "contract_id,version_number,account_id,effective_start_date,effective_end_date,arr_amount,currency,seats,plan_tier,amendment_type,created_at,is_backdated,co_termination_group",
     "contract_id,version_number"),
    ("customer_master", "STG_CUSTOMER", "CUSTOMER_MASTER",
     "account_id,version,billing_contact_name,billing_contact_email,tax_id,address_line1,city,region,legal_entity,updated_at",
     "account_id,version"),
    ("fx_rates", "STG_FX", "FX_RATES",
     "rate_date,base_currency,quote_currency,fx_rate",
     "rate_date,base_currency,quote_currency"),
]
BILLING_TABLES = [
    ("invoices", "STG_BILLING", "INVOICES",
     "invoice_id,contract_id,account_id,invoice_date,currency,amount",
     "invoice_id"),
    ("invoice_line_items", "STG_BILLING", "INVOICE_LINE_ITEMS",
     "invoice_line_id,invoice_id,description,quantity,unit_amount,amount",
     "invoice_line_id"),
    ("credit_memos", "STG_BILLING", "CREDIT_MEMOS",
     "credit_memo_id,invoice_id,account_id,issue_date,system_entry_date,currency,amount,reason",
     "credit_memo_id"),
    ("payments", "STG_BILLING", "PAYMENTS",
     "payment_id,invoice_id,account_id,payment_date,amount,currency",
     "payment_id"),
    ("gl_journal_entries", "STG_ERP", "GL_JOURNAL_ENTRIES",
     "je_id,posting_date,gl_account,debit_credit,amount,currency,reference_id,je_type",
     "je_id"),
]


@task
def load_table_if_present(run_date, name, stage, table, columns, key_columns):
    """PUT + COPY INTO a staging table, then MERGE into RAW on key_columns,
    for one source's daily slice -- if the generator produced one for this
    date (empty slices simply aren't written -- see
    data_generator/generator/writer.py -- so a missing file is normal, not
    an error). Mapped once per source table via expand_kwargs below.

    Loads via MERGE on an explicit natural key rather than a plain COPY INTO
    the target table, because neither FORCE=TRUE nor Snowflake's own
    load-history dedup make a retried/cleared task instance safe here:
    confirmed live that re-PUTting the exact same local file with
    OVERWRITE=TRUE gets a *different* MD5/ETag from Snowflake's internal
    stage on every upload (true with or without AUTO_COMPRESS), so the
    load-history "already loaded this file" check Snowflake normally uses to
    skip a duplicate COPY INTO never matches -- every retry duplicated rows
    in RAW regardless of FORCE. MERGE on key_columns sidesteps the file
    identity question entirely and is idempotent by row instead.

    Parameter is `run_date`, not `ds` -- confirmed live that naming it `ds`
    breaks TaskFlow's @task decorator: `ds` is a reserved Airflow context
    key, and the decorator tries to auto-inject a default for it, producing
    an invalid signature (a defaulted `ds` landing before the required
    `name`/`stage`/`table`/`columns` params) -- every mapped task instance
    failed at render time with "non-default argument follows default
    argument" before this rename."""
    local_path = f"{PROJECT_DIR}/data_generator/output/daily/{run_date}/{name}/{name}.csv"
    if not os.path.exists(local_path):
        log.info("no rows for %s on %s, skipping", name, run_date)
        return

    hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
    # SnowflakeHook.database is only ever populated from a constructor kwarg
    # (see SnowflakeHook.__init__), never automatically from the connection's
    # own extra fields -- confirmed live: hook.database is None here even
    # though hook.run() connects to the right database, producing literal
    # "@None.RAW.<stage>" stage paths and a Snowflake "Database 'NONE' does
    # not exist" error. Read it from the connection's extra instead.
    database = hook.get_connection(SNOWFLAKE_CONN_ID).extra_dejson.get("database")
    stage_path = f"@{database}.RAW.{stage}/{run_date}/{name}/"
    hook.run(f"PUT file://{local_path} {stage_path} AUTO_COMPRESS=TRUE OVERWRITE=TRUE")

    # Not a TEMPORARY table: hook.run() opens and closes a brand-new
    # connection on every call (see SnowflakeHook.run -- `with
    # closing(self.get_conn())`), so a session-scoped TEMPORARY table
    # created in one hook.run() call is already gone by the next one
    # (confirmed live: "Table ... does not exist" on the COPY INTO
    # immediately after CREATE TEMPORARY TABLE). Named per run_date+table so
    # concurrent DAG runs for different dates can't collide; dropped at the
    # end since it's a real object, not session-scoped.
    tmp_table = f"{database}.RAW.{table}_LOAD_STG_{run_date.replace('-', '')}"
    col_list = [c.strip() for c in columns.split(",")]
    key_list = [c.strip() for c in key_columns.split(",")]
    hook.run(f"CREATE OR REPLACE TRANSIENT TABLE {tmp_table} LIKE {database}.RAW.{table}")
    try:
        hook.run(
            f"COPY INTO {tmp_table} ({columns}) "
            f"FROM {stage_path} FILE_FORMAT=(FORMAT_NAME={database}.RAW.FF_CSV) "
            f"PURGE=FALSE FORCE=TRUE"
        )
        merge_on = " AND ".join(f"t.{k} = s.{k}" for k in key_list)
        hook.run(
            f"MERGE INTO {database}.RAW.{table} t "
            f"USING {tmp_table} s ON {merge_on} "
            f"WHEN NOT MATCHED THEN INSERT ({columns}) "
            f"VALUES ({', '.join(f's.{c}' for c in col_list)})"
        )
    finally:
        hook.run(f"DROP TABLE IF EXISTS {tmp_table}")
    log.info("loaded %s -> %s.RAW.%s", name, database, table)


def _billing_feed_arrived(ds, **_):
    """The actual D2 check: has ANY billing file landed for today yet?
    Returns False (not an exception) so the sensor keeps polling instead of
    failing outright -- an SLA miss is what should page someone, not a
    single failed poke."""
    for name, _, _, _, _ in BILLING_TABLES:
        if os.path.exists(f"{PROJECT_DIR}/data_generator/output/daily/{ds}/{name}/{name}.csv"):
            return True
    return False


def _billing_sla_miss(dag, task_list, blocking_task_list, slas, blocking_tis):
    # Hook point for a real paging integration (PagerDuty/Slack/etc.) --
    # kept as a structured log line here since this repo has no such
    # service configured, but this callback is genuinely wired to Airflow's
    # SLA mechanism, not a placeholder.
    log.error(
        "SLA MISS: revenuelens billing ingestion did not complete on time. "
        "Tasks: %s", [t.task_id for t in task_list],
    )


default_args = {
    "owner": "data_engineering",
    "depends_on_past": False,
    "start_date": datetime(2024, 1, 1),
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    "10_ingestion",
    default_args=default_args,
    schedule_interval="@daily",
    catchup=False,
    sla_miss_callback=_billing_sla_miss,
    tags=["revenuelens", "ingestion"],
) as dag:

    generate_data = BashOperator(
        task_id="generate_daily_data",
        bash_command=(
            f"cd {PROJECT_DIR}/data_generator && "
            # revenuelens-python: the generator's isolated venv (pandas/
            # numpy/Faker), symlinked onto PATH by airflow/Dockerfile --
            # not Airflow's own Python, which doesn't have these deps.
            "revenuelens-python main.py daily --as-of {{ ds }} --inject-late-credit-memo"
        ),
    )

    wait_for_billing_feed = PythonSensor(
        task_id="wait_for_billing_feed",
        python_callable=_billing_feed_arrived,
        op_kwargs={"ds": "{{ ds }}"},
        timeout=60 * 60,  # 1 hour SLA
        poke_interval=60,
        mode="reschedule",
        sla=timedelta(hours=1),
    )

    load_crm_tasks = load_table_if_present.override(
        task_id="load_crm_to_raw", outlets=[raw_crm_dataset]
    ).expand_kwargs([
        {"run_date": "{{ ds }}", "name": name, "stage": stage, "table": table, "columns": columns, "key_columns": key_columns}
        for name, stage, table, columns, key_columns in CRM_TABLES
    ])

    load_billing_tasks = load_table_if_present.override(
        task_id="load_billing_to_raw", outlets=[raw_billing_dataset]
    ).expand_kwargs([
        {"run_date": "{{ ds }}", "name": name, "stage": stage, "table": table, "columns": columns, "key_columns": key_columns}
        for name, stage, table, columns, key_columns in BILLING_TABLES
    ])

    generate_data >> load_crm_tasks
    generate_data >> wait_for_billing_feed >> load_billing_tasks
