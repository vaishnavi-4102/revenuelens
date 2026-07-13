"""Deploys demo/dashboard/streamlit_app.py as a real Streamlit-in-Snowflake
app via CREATE STREAMLIT -- no Snowsight UI click-through needed. Re-run
any time streamlit_app.py changes; CREATE OR REPLACE + PUT ... OVERWRITE
make this safe to run repeatedly.

Usage: python deploy_dashboard.py [RL_DEV|RL_QA|RL_PROD]  (default RL_PROD)

Requires SNOWFLAKE_ACCOUNT / SNOWFLAKE_USER / SNOWFLAKE_PASSWORD in the
environment, same as the rest of this project.
"""
import os
import sys

import snowflake.connector

DATABASE = sys.argv[1] if len(sys.argv) > 1 else "RL_PROD"
APP_NAME = "RL_CFO_ARR_DASHBOARD"
STAGE_NAME = "STREAMLIT_APPS"
LOCAL_FILE = os.path.join(os.path.dirname(__file__), "dashboard", "streamlit_app.py")

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    role="RL_TRANSFORMER",
    warehouse="RL_BI_WH",
    database=DATABASE,
    schema="MARTS_FINANCE",
)
cur = conn.cursor()

cur.execute(f"CREATE STAGE IF NOT EXISTS {DATABASE}.MARTS_FINANCE.{STAGE_NAME}")
cur.execute(f"PUT file://{LOCAL_FILE} @{DATABASE}.MARTS_FINANCE.{STAGE_NAME}/{APP_NAME}/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE")
cur.execute(f"""
    CREATE OR REPLACE STREAMLIT {DATABASE}.MARTS_FINANCE.{APP_NAME}
        ROOT_LOCATION = '@{DATABASE}.MARTS_FINANCE.{STAGE_NAME}/{APP_NAME}'
        MAIN_FILE = 'streamlit_app.py'
        QUERY_WAREHOUSE = RL_BI_WH
        TITLE = 'RevenueLens — CFO ARR Dashboard'
        COMMENT = 'D1 demo: ARR waterfall, one number one definition. See dbt exposure cfo_arr_dashboard for lineage.'
""")

cur.execute(f"SHOW STREAMLITS LIKE '{APP_NAME}' IN SCHEMA {DATABASE}.MARTS_FINANCE")
row = cur.fetchone()
cols = [d[0] for d in cur.description]
info = dict(zip(cols, row))
print(f"Deployed {DATABASE}.MARTS_FINANCE.{APP_NAME}")
print(f"  url_id: {info.get('url_id')}")
print(f"  owner: {info.get('owner')}")

conn.close()
