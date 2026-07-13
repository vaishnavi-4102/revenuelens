-- Billed vs. Recognized vs. Collected vs. Credits, all converted to USD at
-- each transaction's own date/currency, broken out by legal_entity (row
-- access scoped the same way dim_customer is) and month.
--
-- Revenue recognition is simplified to recognized-on-invoice-period (per
-- spec guardrails), so Deferred is always 0. Credit memos ARE netted into
-- recognized_net_of_credits_usd -- that's the whole point of this being
-- incremental: a credit memo can land weeks after its invoice_date/period
-- already looked closed (issue_date vs. system_entry_date lag), and this
-- model's job is to notice and selectively reprocess just the affected
-- (month, legal_entity), not the full 24-month history.
--
-- Incremental strategy: recompute full totals for EVERY month (never a
-- partial delta -- that would understate a reprocessed month), but only
-- WRITE OUT rows for (month_start, legal_entity) pairs touched by a
-- recently-landed row within reprocess_lookback_days. delete+insert on
-- that key replaces exactly the reprocessed months; everything else in the
-- table is untouched. rpt_restatement_log (downstream) records which keys
-- got touched by the most recent run.
{% set lookback_days = var('reprocess_lookback_days', 60) %}

{{
    config(
        materialized='incremental',
        unique_key=['month_start', 'legal_entity'],
        incremental_strategy='delete+insert',
        post_hook=[
            "{% if not is_incremental() %}alter table {{ this }} add row access policy {{ target.database }}.MARTS_FINANCE.ENTITY_ACCESS_POLICY on (legal_entity){% else %}select 1{% endif %}"
        ]
    )
}}

with fx as (

    select rate_date, quote_currency, fx_rate from {{ ref('int_fx_rates_daily_filled') }}

),

accounts as (

    select account_id, legal_entity from {{ ref('stg_crm__accounts') }}

),

invoices_usd as (

    select
        date_trunc('month', i.invoice_date) as month_start,
        a.legal_entity,
        i.amount / nullif(fx.fx_rate, 0) as amount_usd,
        i._loaded_at
    from {{ ref('stg_billing__invoices') }} i
    left join accounts a on a.account_id = i.account_id
    left join fx on fx.rate_date = i.invoice_date and fx.quote_currency = i.currency

),

credit_memos_usd as (

    select
        date_trunc('month', cm.issue_date) as month_start,
        a.legal_entity,
        cm.amount / nullif(fx.fx_rate, 0) as amount_usd,
        cm.system_entry_date
    from {{ ref('stg_billing__credit_memos') }} cm
    left join accounts a on a.account_id = cm.account_id
    left join fx on fx.rate_date = cm.issue_date and fx.quote_currency = cm.currency

),

payments_usd as (

    select
        date_trunc('month', p.payment_date) as month_start,
        a.legal_entity,
        p.amount / nullif(fx.fx_rate, 0) as amount_usd,
        p._loaded_at
    from {{ ref('stg_billing__payments') }} p
    left join accounts a on a.account_id = p.account_id
    left join fx on fx.rate_date = p.payment_date and fx.quote_currency = p.currency

),

gl_usd as (

    select
        date_trunc('month', g.posting_date) as month_start,
        a.legal_entity,
        g.gl_account,
        g.debit_credit,
        g.je_type,
        g.amount / nullif(fx.fx_rate, 0) as amount_usd,
        g._loaded_at
    from {{ ref('stg_erp__gl_journal_entries') }} g
    left join {{ ref('stg_billing__invoices') }} i on i.invoice_id = g.invoice_id
    left join accounts a on a.account_id = i.account_id
    left join fx on fx.rate_date = g.posting_date and fx.quote_currency = g.currency

),

billed as (
    select month_start, legal_entity, sum(amount_usd) as billed_usd
    from invoices_usd group by 1, 2
),

credits as (
    select month_start, legal_entity, sum(amount_usd) as credit_usd
    from credit_memos_usd group by 1, 2
),

collected as (
    select month_start, legal_entity, sum(amount_usd) as collected_usd
    from payments_usd group by 1, 2
),

recognized as (

    select
        month_start,
        legal_entity,
        sum(case
            when gl_account = '4000-SUBSCRIPTION-REVENUE' and debit_credit = 'CREDIT' then amount_usd
            when gl_account = '4000-SUBSCRIPTION-REVENUE' and debit_credit = 'DEBIT' then -amount_usd
            else 0
        end) as recognized_usd,
        sum(case
            when je_type = 'MANUAL_ADJUSTMENT' and gl_account = '4000-SUBSCRIPTION-REVENUE' and debit_credit = 'CREDIT' then amount_usd
            when je_type = 'MANUAL_ADJUSTMENT' and gl_account = '4000-SUBSCRIPTION-REVENUE' and debit_credit = 'DEBIT' then -amount_usd
            else 0
        end) as manual_adjustment_usd
    from gl_usd
    group by 1, 2

),

months_x_entities as (
    select month_start, legal_entity from billed
    union select month_start, legal_entity from credits
    union select month_start, legal_entity from collected
    union select month_start, legal_entity from recognized
),

affected_keys as (
    -- Only consulted when is_incremental() -- see final filter below.
    select month_start, legal_entity from invoices_usd
        where _loaded_at >= dateadd(day, -{{ lookback_days }}, {{ as_of_timestamp() }})
    union
    select month_start, legal_entity from credit_memos_usd
        where system_entry_date >= dateadd(day, -{{ lookback_days }}, {{ as_of_date() }})
    union
    select month_start, legal_entity from payments_usd
        where _loaded_at >= dateadd(day, -{{ lookback_days }}, {{ as_of_timestamp() }})
    union
    select month_start, legal_entity from gl_usd
        where _loaded_at >= dateadd(day, -{{ lookback_days }}, {{ as_of_timestamp() }})
),

final as (

    select
        m.month_start,
        m.legal_entity,
        coalesce(b.billed_usd, 0) as billed_usd,
        coalesce(r.recognized_usd, 0) as recognized_usd,
        coalesce(cr.credit_usd, 0) as credit_usd,
        coalesce(co.collected_usd, 0) as collected_usd,
        coalesce(r.manual_adjustment_usd, 0) as manual_adjustment_usd,
        round(coalesce(r.recognized_usd, 0) - coalesce(cr.credit_usd, 0), 2) as recognized_net_of_credits_usd
    from months_x_entities m
    left join billed b on b.month_start = m.month_start and b.legal_entity = m.legal_entity
    left join recognized r on r.month_start = m.month_start and r.legal_entity = m.legal_entity
    left join credits cr on cr.month_start = m.month_start and cr.legal_entity = m.legal_entity
    left join collected co on co.month_start = m.month_start and co.legal_entity = m.legal_entity

)

select * from final
{% if is_incremental() %}
where (month_start, legal_entity) in (select month_start, legal_entity from affected_keys)
{% endif %}
order by 1, 2
