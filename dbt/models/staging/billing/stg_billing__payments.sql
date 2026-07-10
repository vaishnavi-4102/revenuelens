-- Deduplicates true duplicate payment records: the source system
-- occasionally writes the same real-world payment twice under two different
-- payment_ids. Those duplicates share (invoice_id, payment_date, amount,
-- currency) exactly, which is what distinguishes them from a legitimate
-- partial payment (different amount, same invoice/date) -- partial payments
-- must NOT be collapsed. Ties within a duplicate group are broken by the
-- lowest payment_id so the result is deterministic across re-runs.

with source as (

    select * from {{ source('billing', 'payments') }}

),

deduplicated as (

    select
        payment_id,
        invoice_id,
        account_id,
        payment_date,
        amount,
        currency,
        _loaded_at,
        row_number() over (
            partition by invoice_id, payment_date, amount, currency
            order by payment_id
        ) as duplicate_rank

    from source

),

renamed as (

    select
        payment_id,
        invoice_id,
        account_id,
        payment_date,
        amount,
        currency,
        _loaded_at

    from deduplicated
    where duplicate_rank = 1

)

select * from renamed
