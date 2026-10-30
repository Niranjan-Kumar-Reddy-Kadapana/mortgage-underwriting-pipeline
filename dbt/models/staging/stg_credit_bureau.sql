select
    applicant_id,
    nullif(regexp_replace(ssn, '[^0-9]', ''), '')        as ssn,
    try_to_number(fico_score)                            as fico_score,
    try_to_decimal(monthly_debt, 14, 2)                  as monthly_debt_obligations,
    try_to_date(report_date)                             as credit_report_date,
    _source_file                                         as source_file,
    _loaded_at                                           as loaded_at
from {{ source('bronze', 'raw_credit_bureau') }}
where applicant_id is not null
qualify row_number() over (
    partition by applicant_id
    order by credit_report_date desc nulls last, _loaded_at desc
) = 1
