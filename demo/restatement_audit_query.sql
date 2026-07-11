-- D2 restatement audit: shows the literal before/after of a reprocessed
-- period, using Snowflake Time Travel + rpt_restatement_log's record of
-- which (month_start, legal_entity) keys the most recent dbt run touched.
--
-- Usage: after running `dbt run --select fct_revenue_reconciliation_monthly
-- rpt_restatement_log` following a late credit memo landing, run this with
-- {{ run_started_at }} set to the MAX(run_started_at) from
-- rpt_restatement_log for this invocation.

-- 1. Which periods did this run touch, and when did the run start?
select run_started_at, dbt_invocation_id, month_start, legal_entity
from RL_PROD.MARTS_FINANCE.RPT_RESTATEMENT_LOG
where run_started_at = (select max(run_started_at) from RL_PROD.MARTS_FINANCE.RPT_RESTATEMENT_LOG);

-- 2. Before: state of the reprocessed period immediately before this run
-- (swap in the run_started_at from query 1).
select *
from RL_PROD.MARTS_FINANCE.FCT_REVENUE_RECONCILIATION_MONTHLY
    before(timestamp => '<run_started_at from query 1>'::timestamp_ntz)
where month_start = '<month_start from query 1>'
  and legal_entity = '<legal_entity from query 1>';

-- 3. After: current state of the same period, post-reprocess.
select *
from RL_PROD.MARTS_FINANCE.FCT_REVENUE_RECONCILIATION_MONTHLY
where month_start = '<month_start from query 1>'
  and legal_entity = '<legal_entity from query 1>';

-- The delta between (2) and (3) -- specifically credit_usd and
-- recognized_net_of_credits_usd moving -- is the live "what changed since
-- I last looked, and why" answer for the CFO.
