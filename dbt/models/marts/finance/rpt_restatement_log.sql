-- Append-only log of which (month_start, legal_entity) keys
-- fct_revenue_reconciliation_monthly reprocessed on each run -- the "what
-- changed since I last looked" answer the CFO can't get today (see problem
-- doc §1). Doesn't store before/after values itself: pair a row here with
-- a Snowflake Time Travel query against fct_revenue_reconciliation_monthly
-- `AT(TIMESTAMP => <this row's run_started_at>)` vs. the current table
-- state for the literal diff -- see demo/restatement_audit_query.sql.
--
-- On the very first build, every (month, legal_entity) is "reprocessed"
-- (there's no prior state) -- that's the initial load, not a restatement.
-- Every run after that, only genuinely late-arriving data produces rows
-- here, which is what makes this the D2 audit trail.
{{ config(materialized='incremental') }}

{% set lookback_days = var('reprocess_lookback_days', 60) %}

with accounts as (

    select account_id, legal_entity from {{ ref('stg_crm__accounts') }}

),

invoices_affected as (
    select date_trunc('month', i.invoice_date) as month_start, a.legal_entity
    from {{ ref('stg_billing__invoices') }} i
    left join accounts a on a.account_id = i.account_id
    where i._loaded_at >= dateadd(day, -{{ lookback_days }}, current_timestamp())
),

credit_memos_affected as (
    select date_trunc('month', cm.issue_date) as month_start, a.legal_entity
    from {{ ref('stg_billing__credit_memos') }} cm
    left join accounts a on a.account_id = cm.account_id
    where cm.system_entry_date >= dateadd(day, -{{ lookback_days }}, current_date())
),

payments_affected as (
    select date_trunc('month', p.payment_date) as month_start, a.legal_entity
    from {{ ref('stg_billing__payments') }} p
    left join accounts a on a.account_id = p.account_id
    where p._loaded_at >= dateadd(day, -{{ lookback_days }}, current_timestamp())
),

gl_affected as (
    select date_trunc('month', g.posting_date) as month_start, a.legal_entity
    from {{ ref('stg_erp__gl_journal_entries') }} g
    left join {{ ref('stg_billing__invoices') }} i on i.invoice_id = g.invoice_id
    left join accounts a on a.account_id = i.account_id
    where g._loaded_at >= dateadd(day, -{{ lookback_days }}, current_timestamp())
),

affected_keys as (
    select month_start, legal_entity from invoices_affected
    union select month_start, legal_entity from credit_memos_affected
    union select month_start, legal_entity from payments_affected
    union select month_start, legal_entity from gl_affected
)

select
    current_timestamp() as run_started_at,
    '{{ invocation_id }}' as dbt_invocation_id,
    month_start,
    legal_entity
from affected_keys
