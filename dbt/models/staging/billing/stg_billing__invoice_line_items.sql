with source as (

    select * from {{ source('billing', 'invoice_line_items') }}

),

renamed as (

    select
        invoice_line_id,
        invoice_id,
        description,
        quantity,
        unit_amount,
        amount,
        _loaded_at

    from source

)

select * from renamed
