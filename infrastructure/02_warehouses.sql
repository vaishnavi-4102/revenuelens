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

CREATE WAREHOUSE IF NOT EXISTS RL_BI_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
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
