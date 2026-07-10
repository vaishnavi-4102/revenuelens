-- RevenueLens :: Database & Schema layout
-- One database per environment; one schema per pipeline layer within each.
-- Idempotent: safe to re-run.
--
-- Layout:
--   RL_DEV / RL_QA / RL_PROD
--     RAW               -- landed exactly as ingested, no transformation
--     STAGING           -- source-conformed (dbt staging/)
--     INTERMEDIATE      -- reusable building blocks (dbt intermediate/)
--     MARTS_FINANCE     -- consumption-grade marts (dbt marts/finance/)

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS RL_DEV
    COMMENT = 'RevenueLens - developer sandbox environment';
CREATE DATABASE IF NOT EXISTS RL_QA
    COMMENT = 'RevenueLens - QA / integration environment (auto-deployed on merge to main)';
CREATE DATABASE IF NOT EXISTS RL_PROD
    COMMENT = 'RevenueLens - production environment (deployed on tagged release)';

-- Schemas: identical layer set in every environment.
CREATE SCHEMA IF NOT EXISTS RL_DEV.RAW;
CREATE SCHEMA IF NOT EXISTS RL_DEV.STAGING;
CREATE SCHEMA IF NOT EXISTS RL_DEV.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS RL_DEV.MARTS_FINANCE;

CREATE SCHEMA IF NOT EXISTS RL_QA.RAW;
CREATE SCHEMA IF NOT EXISTS RL_QA.STAGING;
CREATE SCHEMA IF NOT EXISTS RL_QA.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS RL_QA.MARTS_FINANCE;

CREATE SCHEMA IF NOT EXISTS RL_PROD.RAW;
CREATE SCHEMA IF NOT EXISTS RL_PROD.STAGING;
CREATE SCHEMA IF NOT EXISTS RL_PROD.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS RL_PROD.MARTS_FINANCE;

-- PROD Time Travel retention bumped up so the restatement demo (D2) can
-- always show pre-restatement state on request. 90 days requires Enterprise
-- edition or above; Standard edition caps at 1 day (this ALTER will error on
-- Standard -- drop to 1 if the trial account is Standard edition).
ALTER DATABASE RL_PROD SET DATA_RETENTION_TIME_IN_DAYS = 90;
ALTER DATABASE RL_QA   SET DATA_RETENTION_TIME_IN_DAYS = 7;
ALTER DATABASE RL_DEV  SET DATA_RETENTION_TIME_IN_DAYS = 1;
