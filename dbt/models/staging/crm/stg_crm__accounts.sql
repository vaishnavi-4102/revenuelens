with source as (

    select * from {{ source('crm', 'accounts') }}

),

renamed as (

    select
        account_id,
        account_name,
        region,
        legal_entity,
        currency,
        segment,
        industry,
        created_date as account_created_date,
        _loaded_at

    from source

)

select * from renamed
