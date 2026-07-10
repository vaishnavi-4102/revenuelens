-- Deliberately no filtering or deduplication here: every credit memo,
-- however late system_entry_date is relative to issue_date, must reach the
-- restatement/reprocessing logic downstream untouched. Collapsing or
-- dropping rows in staging would hide exactly the signal the D2 demo
-- (and the lookback-window reprocessing strategy) depends on.

with source as (

    select * from {{ source('billing', 'credit_memos') }}

),

renamed as (

    select
        credit_memo_id,
        invoice_id,
        account_id,
        issue_date,
        system_entry_date,
        currency,
        amount,
        reason,
        _loaded_at

    from source

)

select * from renamed
