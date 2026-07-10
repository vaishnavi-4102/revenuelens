with source as (

    select * from {{ source('fx', 'fx_rates') }}

),

renamed as (

    select
        rate_date,
        base_currency,
        quote_currency,
        fx_rate,
        _loaded_at

    from source

)

select * from renamed
