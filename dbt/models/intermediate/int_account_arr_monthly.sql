-- Account-level ARR rollup, plus the account-level history flags the
-- classification mart needs to tell "new logo" apart from "reactivation"
-- (both look identical at the contract grain -- a contract's first month
-- with prior_account_arr = 0 -- the difference is whether the account ever
-- had any ARR before that gap).
with contract_month as (

    select * from {{ ref('int_contract_arr_monthly') }}

),

by_account as (

    select
        month_end_date,
        account_id,
        region,
        legal_entity,
        sum(arr_usd) as account_arr_usd
    from contract_month
    group by 1, 2, 3, 4

),

with_history as (

    select
        *,
        lag(account_arr_usd) over (partition by account_id order by month_end_date) as prior_account_arr_usd,
        max(account_arr_usd) over (
            partition by account_id order by month_end_date
            rows between unbounded preceding and 1 preceding
        ) as max_prior_account_arr_usd
    from by_account

)

select
    month_end_date,
    account_id,
    region,
    legal_entity,
    account_arr_usd,
    coalesce(prior_account_arr_usd, 0) as prior_account_arr_usd,
    (coalesce(max_prior_account_arr_usd, 0) > 0) as account_ever_had_arr_before
from with_history
