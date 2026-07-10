with source as (

    select * from {{ source('erp', 'gl_journal_entries') }}

),

renamed as (

    select
        je_id,
        posting_date,
        gl_account,
        debit_credit,
        amount,
        currency,
        reference_id as invoice_id,
        je_type,
        _loaded_at

    from source

)

select * from renamed
