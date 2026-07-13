-- RevenueLens :: Warehouses
-- One warehouse per workload class, shared across DEV/QA/PROD (env isolation
-- comes from the database layer + RBAC, not from duplicating warehouses).
-- Small + auto-suspend=60s everywhere: this is a demo asset, not a
-- production workload, and short suspend windows make the D5 cost story
-- ("you'll know your bill by workload") legible on a trial account.
-- Idempotent: safe to re-run.

USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS RL_LOADING_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'RevenueLens - ingestion / COPY INTO / Snowpipe / Streams-Tasks workload';

CREATE WAREHOUSE IF NOT EXISTS RL_TRANSFORMING_WH
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'RevenueLens - dbt run/test/snapshot workload';

-- AUTO_SUSPEND = 300, not 60 like the other three -- this is the warehouse
-- the D1 Streamlit dashboard runs on, and 60s was confirmed live to be too
-- aggressive for it specifically: a fresh Streamlit container's cold start
-- (package import, session init) plus render time between the app's own
-- sequential queries was enough for the warehouse to suspend mid-script,
-- surfacing as "No active warehouse selected" on the second query --
-- Streamlit-in-Snowflake's sandboxed session can't self-heal that with a
-- USE WAREHOUSE (confirmed live: that statement type is rejected outright
-- from inside the app). A batch dbt/CI workload doesn't have this
-- interactive cold-start pattern, so the other three warehouses keep the
-- tighter, more cost-conscious 60s.
CREATE WAREHOUSE IF NOT EXISTS RL_BI_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'RevenueLens - Snowsight dashboard / ad-hoc analyst queries';

-- CI runs (Slim CI against zero-copy clones) get their own warehouse so
-- pipeline cost and CI cost are never conflated in the D5 cost-attribution view.
CREATE WAREHOUSE IF NOT EXISTS RL_CI_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'RevenueLens - GitHub Actions Slim CI (dbt build against PROD clone)';
