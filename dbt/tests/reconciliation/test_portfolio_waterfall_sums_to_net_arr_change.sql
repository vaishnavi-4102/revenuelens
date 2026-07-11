-- Definition of Done: "waterfall movements sum to net ARR change" at the
-- portfolio (company-wide) grain -- the number the CFO dashboard reads.
select
    month_end_date,
    total_arr_usd,
    prior_total_arr_usd,
    net_movement_usd,
    round((total_arr_usd - coalesce(prior_total_arr_usd, 0)) - net_movement_usd, 2) as reconciliation_gap
from {{ ref('fct_arr_waterfall_portfolio_monthly') }}
where abs((total_arr_usd - coalesce(prior_total_arr_usd, 0)) - net_movement_usd) > 0.01
