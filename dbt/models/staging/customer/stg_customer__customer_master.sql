with source as (

    select * from {{ source('customer', 'customer_master') }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['account_id', 'version']) }} as customer_master_sk,
        account_id,
        version as customer_master_version,
        billing_contact_name,
        billing_contact_email,
        tax_id,
        address_line1,
        city,
        region,
        legal_entity,
        updated_at,
        _loaded_at

    from source

)

select * from renamed
