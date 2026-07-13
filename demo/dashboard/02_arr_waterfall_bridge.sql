-- D1 tile 2: the ARR waterfall bridge for the most recent month --
-- Starting ARR -> New -> Expansion -> Reactivation -> Contraction -> Churn
-- -> FX Impact -> Ending ARR.
--
-- Snowsight has no native waterfall chart type, so this uses the standard
-- "invisible base + visible delta" trick: base_invisible is plotted as a
-- transparent series, bar_visible stacks on top of it, so each bar appears
-- to float at the right height instead of starting from zero.
--
-- Snowsight setup:
--   1. Chart type: Bar, subtype Stacked.
--   2. X-axis: category (do NOT let Snowsight re-sort it -- if it does,
--      add sort_order as a secondary sort / hidden column and sort by it).
--   3. Y-axis: two series, base_invisible and bar_visible, stacked.
--   4. Series colors: set base_invisible's fill to fully transparent /
--      matching the dashboard background. Color bar_visible green for
--      New/Expansion/Reactivation, red for Contraction/Churn, blue for
--      Starting ARR/Ending ARR, grey for FX Impact.
--   5. To demo a different month, edit the `where` clause below or add a
--      Snowsight dashboard filter on month_end_date.
with selected_month as (

    select *
    from marts_finance.fct_arr_waterfall_portfolio_monthly
    where month_end_date = (select max(month_end_date) from marts_finance.fct_arr_waterfall_portfolio_monthly)

),

components as (
    select 1 as sort_order, 'Starting ARR' as category, coalesce(prior_total_arr_usd, 0) as delta from selected_month
    union all select 2, 'New',          new_arr_usd          from selected_month
    union all select 3, 'Expansion',    expansion_arr_usd     from selected_month
    union all select 4, 'Reactivation', reactivation_arr_usd  from selected_month
    union all select 5, 'Contraction',  contraction_arr_usd   from selected_month
    union all select 6, 'Churn',        churn_arr_usd         from selected_month
    union all select 7, 'FX Impact',    fx_impact_usd         from selected_month
),

running as (

    select
        sort_order,
        category,
        delta,
        sum(delta) over (order by sort_order rows between unbounded preceding and current row) as running_total,
        coalesce(
            sum(delta) over (order by sort_order rows between unbounded preceding and 1 preceding),
            0
        ) as running_before
    from components

)

select
    sort_order,
    category,
    least(running_before, running_total) as base_invisible,
    abs(delta) as bar_visible,
    delta as raw_delta
from running

union all

select
    8 as sort_order,
    'Ending ARR' as category,
    0 as base_invisible,
    total_arr_usd as bar_visible,
    total_arr_usd as raw_delta
from selected_month

order by sort_order
