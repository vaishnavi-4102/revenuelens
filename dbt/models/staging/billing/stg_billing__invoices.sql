with source as (

    select * from {{ source('billing', 'invoices') }}

),

renamed as (

    select
        invoice_id,
        contract_id,
        account_id,
        invoice_date,
        currency,
        amount,
        _loaded_at

    from source

)

select * from renamed
