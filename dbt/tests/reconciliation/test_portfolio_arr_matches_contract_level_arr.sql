-- Cross-checks two independently-derived totals: the portfolio mart's
-- rolled-up total_arr_usd vs. summing int_contract_arr_monthly directly.
-- These should always match exactly -- if they don't, something in the
-- bridge/classification/rollup chain is silently dropping or double
-- counting contract-months.
with from_portfolio as (

    select month_end_date, total_arr_usd
    from {{ ref('fct_arr_waterfall_portfolio_monthly') }}

),

from_contracts as (

    select month_end_date, sum(arr_usd) as total_arr_usd
    from {{ ref('int_contract_arr_monthly') }}
    group by 1

)

select
    p.month_end_date,
    p.total_arr_usd as portfolio_total_arr_usd,
    c.total_arr_usd as contract_level_total_arr_usd,
    round(p.total_arr_usd - c.total_arr_usd, 2) as reconciliation_gap
from from_portfolio p
join from_contracts c on c.month_end_date = p.month_end_date
where abs(p.total_arr_usd - c.total_arr_usd) > 0.01
