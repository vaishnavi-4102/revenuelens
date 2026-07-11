-- Same invariant as test_portfolio_waterfall_sums_to_net_arr_change, but at
-- account grain -- catches decomposition bugs that cancel out at the
-- portfolio level (e.g. a downgrade and an upsell on two co-terminated
-- contracts netting to the right total by coincidence).
with acct as (

    select
        month_end_date,
        account_id,
        account_arr_usd,
        lag(account_arr_usd) over (partition by account_id order by month_end_date) as prior_account_arr_usd,
        (new_arr_usd + expansion_arr_usd + contraction_arr_usd + churn_arr_usd + reactivation_arr_usd + fx_impact_usd) as net_movement_usd
    from {{ ref('fct_arr_waterfall_account_monthly') }}

)

select
    account_id,
    month_end_date,
    account_arr_usd,
    prior_account_arr_usd,
    net_movement_usd,
    round((account_arr_usd - coalesce(prior_account_arr_usd, 0)) - net_movement_usd, 2) as reconciliation_gap
from acct
where abs((account_arr_usd - coalesce(prior_account_arr_usd, 0)) - net_movement_usd) > 0.01
