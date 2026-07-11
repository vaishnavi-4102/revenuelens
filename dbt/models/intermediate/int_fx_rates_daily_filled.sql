-- FX rates convention (per fx.py / stg_fx__fx_rates): base_currency is
-- always USD, fx_rate is units of quote_currency per 1 USD. To convert a
-- LOCAL amount in quote_currency to USD, divide by fx_rate.
--
-- fx.py intentionally skips weekends/holidays. This model is the one place
-- that gap gets filled: forward-fill from the last known rate, and for any
-- leading gap before the first observed rate, back-fill from the first
-- known rate. Every downstream USD conversion reads from here, never from
-- stg_fx__fx_rates directly.
with currencies as (

    select 'USD' as quote_currency
    union all select 'EUR'
    union all select 'INR'

),

spine_x_currency as (

    select
        s.date_day as rate_date,
        c.quote_currency
    from {{ ref('int_date_spine_daily') }} s
    cross join currencies c

),

rates as (

    select rate_date, quote_currency, fx_rate
    from {{ ref('stg_fx__fx_rates') }}

),

joined as (

    select
        sxc.rate_date,
        sxc.quote_currency,
        r.fx_rate as fx_rate_observed
    from spine_x_currency sxc
    left join rates r
        on r.rate_date = sxc.rate_date
        and r.quote_currency = sxc.quote_currency

),

filled as (

    select
        rate_date,
        quote_currency,
        fx_rate_observed,
        coalesce(
            {{ fill_forward('fx_rate_observed', 'quote_currency', 'rate_date') }},
            first_value(fx_rate_observed ignore nulls) over (
                partition by quote_currency
                order by rate_date
                rows between current row and unbounded following
            )
        ) as fx_rate
    from joined

)

select
    rate_date,
    quote_currency,
    fx_rate,
    (fx_rate_observed is null) as is_fx_rate_filled
from filled
