-- The highest-risk logic in the whole build (per spec: "a currency change
-- that isn't really an ARR change"). Every month-over-month USD ARR delta
-- gets split into exactly two components that always sum back to the
-- delta by construction:
--
--   real_component_usd  -- this period's LOCAL ARR, revalued at LAST
--                           period's FX rate for whichever currency is in
--                           effect THIS period, minus what was actually
--                           reported last period. If the contract's local
--                           ARR didn't change (no amendment that period),
--                           this is exactly 0 -- a pure FX rate move can
--                           never register here, however large the swing.
--   fx_component_usd    -- the rate-movement effect on this period's
--                           ending local balance. Absorbs pure FX drift
--                           AND the redenomination effect of a
--                           currency_change amendment (the new local
--                           amount, converted at this period's rate for
--                           the new currency, vs. that same amount
--                           converted at last period's rate) -- both are
--                           "not a real ARR move" by the same definition.
--
-- real_component_usd is what drives new/expansion/contraction/churn/
-- reactivation classification downstream; fx_component_usd is reported as
-- its own waterfall bucket. See tests/reconciliation/ for the identity
-- this guarantees.
with contract_month as (

    select * from {{ ref('int_contract_arr_monthly') }}

),

with_prior as (

    select
        cm.*,
        row_number() over (partition by cm.contract_id order by cm.month_end_date) as contract_month_seq,
        lag(cm.month_end_date) over (partition by cm.contract_id order by cm.month_end_date) as prior_month_end_date,
        lag(cm.arr_usd) over (partition by cm.contract_id order by cm.month_end_date) as prior_arr_usd
    from contract_month cm

),

with_prior_fx as (

    select
        wp.*,
        fx_prior.fx_rate as fx_rate_prior_period_same_currency
    from with_prior wp
    left join {{ ref('int_fx_rates_daily_filled') }} fx_prior
        on fx_prior.rate_date = wp.prior_month_end_date
        and fx_prior.quote_currency = coalesce(wp.currency, 'USD')

),

decomposed as (

    select
        *,
        coalesce(prior_arr_usd, 0) as prior_arr_usd_filled,
        case
            -- A contract's first observed month is entirely "real" (new
            -- business) by definition -- there is no prior FX rate to
            -- revalue against.
            when prior_month_end_date is null then arr_usd
            else round(
                (arr_local / nullif(fx_rate_prior_period_same_currency, 0)) - coalesce(prior_arr_usd, 0),
                2
            )
        end as real_component_usd,
        case
            when prior_month_end_date is null then 0
            else round(
                arr_usd - (arr_local / nullif(fx_rate_prior_period_same_currency, 0)),
                2
            )
        end as fx_component_usd
    from with_prior_fx

)

select
    d.month_end_date,
    d.contract_id,
    d.account_id,
    d.region,
    d.legal_entity,
    d.currency,
    d.arr_local,
    d.arr_usd,
    d.contract_month_seq,
    d.prior_arr_usd_filled,
    d.real_component_usd,
    d.fx_component_usd,
    acct.prior_account_arr_usd,
    acct.account_ever_had_arr_before
from decomposed d
left join {{ ref('int_account_arr_monthly') }} acct
    on acct.account_id = d.account_id
    and acct.month_end_date = d.month_end_date
