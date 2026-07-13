-- D1 tile 3: ARR movement trend over time, stacked by movement type --
-- shows the shape of growth (or contraction) across the full 24-month
-- history, not just the current month.
--
-- Snowsight setup: Chart type Bar, subtype Stacked. X-axis: month_end_date.
-- Y-axis: amount_usd. Group/color by: movement_type.
select month_end_date, 'New' as movement_type, new_arr_usd as amount_usd
from marts_finance.fct_arr_waterfall_portfolio_monthly

union all
select month_end_date, 'Expansion', expansion_arr_usd
from marts_finance.fct_arr_waterfall_portfolio_monthly

union all
select month_end_date, 'Reactivation', reactivation_arr_usd
from marts_finance.fct_arr_waterfall_portfolio_monthly

union all
select month_end_date, 'Contraction', contraction_arr_usd
from marts_finance.fct_arr_waterfall_portfolio_monthly

union all
select month_end_date, 'Churn', churn_arr_usd
from marts_finance.fct_arr_waterfall_portfolio_monthly

order by month_end_date, movement_type
