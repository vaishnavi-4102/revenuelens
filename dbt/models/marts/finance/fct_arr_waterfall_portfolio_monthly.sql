-- The D1 headline number: one row per month, one ARR figure, with the full
-- bridge from last month's total to this month's. "One number, one
-- definition" -- everything the CFO dashboard reads comes from this table.
with account_monthly as (

    select * from {{ ref('fct_arr_waterfall_account_monthly') }}

),

agg as (

    select
        month_end_date,
        sum(account_arr_usd) as total_arr_usd,
        sum(new_arr_usd) as new_arr_usd,
        sum(expansion_arr_usd) as expansion_arr_usd,
        sum(contraction_arr_usd) as contraction_arr_usd,
        sum(churn_arr_usd) as churn_arr_usd,
        sum(reactivation_arr_usd) as reactivation_arr_usd,
        sum(fx_impact_usd) as fx_impact_usd
    from account_monthly
    group by 1

)

select
    month_end_date,
    total_arr_usd,
    lag(total_arr_usd) over (order by month_end_date) as prior_total_arr_usd,
    new_arr_usd,
    expansion_arr_usd,
    contraction_arr_usd,
    churn_arr_usd,
    reactivation_arr_usd,
    fx_impact_usd,
    (new_arr_usd + expansion_arr_usd + contraction_arr_usd + churn_arr_usd + reactivation_arr_usd + fx_impact_usd) as net_movement_usd
from agg
order by month_end_date
