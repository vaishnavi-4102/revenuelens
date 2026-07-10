with source as (

    select * from {{ source('crm', 'contracts') }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['contract_id', 'version_number']) }} as contract_version_sk,
        contract_id,
        version_number,
        account_id,
        effective_start_date,
        effective_end_date,
        arr_amount,
        currency,
        seats,
        plan_tier,
        amendment_type,
        created_at as contract_version_recorded_at,
        is_backdated,
        co_termination_group,
        _loaded_at

    from source

)

select * from renamed
