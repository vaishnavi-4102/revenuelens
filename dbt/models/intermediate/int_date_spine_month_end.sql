-- One row per calendar month-end that falls within the observed data
-- window. This is the periodicity the ARR waterfall runs at -- every
-- downstream point-in-time reconstruction joins against this spine.
with daily as (

    select date_day from {{ ref('int_date_spine_daily') }}

),

candidate_month_ends as (

    select distinct
        dateadd(day, -1, dateadd(month, 1, date_trunc('month', date_day))) as month_end_date
    from daily

)

select month_end_date
from candidate_month_ends
-- Drop a trailing partial month -- its "month end" hasn't actually
-- happened yet in the data, so treating it as a real snapshot date would
-- understate that month's activity rather than correctly show it as not
-- yet closed.
where month_end_date <= (select max(date_day) from daily)
order by month_end_date
