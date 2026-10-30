-- Flatten the VARIANT payload, cast safely (bad values become NULL, not load failures),
-- and keep only the latest copy of each application (handles retransmissions).
select
    coalesce(raw:application_id::string, 'NOID-' || md5(raw::string))   as application_id,
    raw:applicant_id::string                                            as applicant_id,
    raw:applicant_name::string                                          as applicant_name,
    try_to_date(raw:application_date::string)                           as application_date,
    try_to_decimal(raw:loan_amount::string, 14, 2)                      as loan_amount,
    try_to_decimal(raw:property_value::string, 14, 2)                   as property_value,
    try_to_decimal(raw:monthly_gross_income::string, 14, 2)             as monthly_gross_income,
    upper(raw:loan_purpose::string)                                     as loan_purpose,
    upper(raw:occupancy_type::string)                                   as occupancy_type,
    upper(raw:property_state::string)                                   as property_state,
    _source_file                                                        as source_file,
    _loaded_at                                                          as loaded_at
from {{ source('bronze', 'raw_mortgage_applications') }}
qualify row_number() over (
    partition by coalesce(raw:application_id::string, 'NOID-' || md5(raw::string))
    order by _loaded_at desc, _source_file desc
) = 1
