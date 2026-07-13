-- Point-in-time ARR per contract per month-end. A contract gets one row for
-- every month-end from its first effective_start_date through either the
-- month it churned (inclusive, at $0 -- this is what lets the bridge model
-- detect the churn event) or the end of the observed window if it's still
-- active. No rows exist before a contract starts or after it churns --
-- this keeps the model to exactly the months that matter instead of
-- carrying $0 rows forever.
with month_spine as (

    select month_end_date from {{ ref('int_date_spine_month_end') }}

),

contract_versions as (

    select * from {{ ref('int_contract_versions') }}

),

contract_bounds as (

    select
        contract_id,
        account_id,
        min(effective_start_date) as contract_first_start,
        max(case when is_churn_version then effective_start_date end) as contract_churn_date
    from contract_versions
    group by 1, 2

),

contract_last_month as (

    select
        cb.contract_id,
        cb.account_id,
        cb.contract_first_start,
        case
            when cb.contract_churn_date is not null
                then (select min(month_end_date) from month_spine where month_end_date >= cb.contract_churn_date)
            else (select max(month_end_date) from month_spine)
        end as contract_last_relevant_month
    from contract_bounds cb

),

contract_months as (

    select
        clm.contract_id,
        clm.account_id,
        m.month_end_date
    from contract_last_month clm
    inner join month_spine m
        on m.month_end_date >= clm.contract_first_start
        and m.month_end_date <= clm.contract_last_relevant_month

),

active_version as (

    select * from contract_versions
    where not is_churn_version

),

-- region/legal_entity from the account, not the active version -- a churn
-- month has no active version (av.region/av.legal_entity would be NULL),
-- and grouping a $0 churn row under a different (NULL) key than the
-- account's other rows silently fans one account/month out into two rows
-- downstream (int_account_arr_monthly's GROUP BY includes both columns).
accounts as (

    select account_id, region, legal_entity, segment
    from {{ ref('stg_crm__accounts') }}

),

joined as (

    select
        cm.month_end_date,
        cm.contract_id,
        cm.account_id,
        a.region,
        a.legal_entity,
        a.segment,
        av.version_number,
        coalesce(av.arr_amount, 0) as arr_local,
        av.currency,
        av.seats,
        av.plan_tier,
        av.amendment_type,
        av.is_backdated,
        av.co_termination_group
    from contract_months cm
    left join accounts a on a.account_id = cm.account_id
    left join active_version av
        on av.contract_id = cm.contract_id
        and av.effective_start_date <= cm.month_end_date
        and cm.month_end_date < av.effective_end_date_exclusive

),

with_fx as (

    select
        j.*,
        fx.fx_rate as fx_rate_at_month_end,
        -- currency is null on a $0 churn-month row (no active version) --
        -- fall back to the contract's own account default currency isn't
        -- meaningful either, so just treat it as USD-denominated $0.
        round(j.arr_local / nullif(fx.fx_rate, 0), 2) as arr_usd
    from joined j
    left join {{ ref('int_fx_rates_daily_filled') }} fx
        on fx.rate_date = j.month_end_date
        and fx.quote_currency = coalesce(j.currency, 'USD')

)

select * from with_fx
