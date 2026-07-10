-- RevenueLens :: Resource Monitors
-- One monitor per warehouse so the D5 cost story ("know your bill by
-- workload") has real credit-quota data to show, not just a QUERY_TAG
-- grouping. Quotas are sized for a demo/POC account, not a production
-- workload -- tune before using this in an always-on environment.
--
-- Note on QUERY_TAG: per-pipeline/per-layer cost attribution (the actual D5
-- "cost per pipeline layer and team" view) comes from setting QUERY_TAG at
-- the session level in dbt (query-comment config in dbt_project.yml) and in
-- every Airflow task (via the Snowflake hook's session_parameters). That's
-- application-layer config, not infra SQL, so it lives in dbt/ and airflow/
-- respectively -- this file only sets the credit-quota guardrails.
--
-- Idempotent: safe to re-run.

USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS RL_LOADING_RM
    WITH CREDIT_QUOTA = 15
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND;

CREATE RESOURCE MONITOR IF NOT EXISTS RL_TRANSFORMING_RM
    WITH CREDIT_QUOTA = 25
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND;

CREATE RESOURCE MONITOR IF NOT EXISTS RL_BI_RM
    WITH CREDIT_QUOTA = 10
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND;

CREATE RESOURCE MONITOR IF NOT EXISTS RL_CI_RM
    WITH CREDIT_QUOTA = 10
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE RL_LOADING_WH SET RESOURCE_MONITOR = RL_LOADING_RM;
ALTER WAREHOUSE RL_TRANSFORMING_WH SET RESOURCE_MONITOR = RL_TRANSFORMING_RM;
ALTER WAREHOUSE RL_BI_WH SET RESOURCE_MONITOR = RL_BI_RM;
ALTER WAREHOUSE RL_CI_WH SET RESOURCE_MONITOR = RL_CI_RM;

-- Account-level backstop so a runaway query/task can't blow the whole trial
-- credit balance even if a per-warehouse monitor is misconfigured later.
CREATE RESOURCE MONITOR IF NOT EXISTS RL_ACCOUNT_RM
    WITH CREDIT_QUOTA = 100
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 80 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER ACCOUNT SET RESOURCE_MONITOR = RL_ACCOUNT_RM;
