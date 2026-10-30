-- Join applications to the bureau on applicant_id and classify every row:
--   VALIDATED          -> goes to Silver
--   PENDING_CREDIT     -> bureau record not here yet but still inside the SLA window: wait, do NOT reject
--   TECHNICAL_REJECTED -> critical field missing/invalid, or bureau SLA breached: logged to technical_rejections
with apps as (
    select * from {{ ref('stg_mortgage_applications') }}
),
credit as (
    select * from {{ ref('stg_credit_bureau') }}
),
joined as (
    select
        a.application_id, a.applicant_id, a.applicant_name, a.application_date,
        a.loan_amount, a.property_value, a.monthly_gross_income,
        a.loan_purpose, a.occupancy_type, a.property_state,
        a.loaded_at                          as app_loaded_at,
        c.ssn, c.fico_score, c.monthly_debt_obligations, c.credit_report_date,
        c.loaded_at                          as credit_loaded_at,
        (c.applicant_id is not null)         as has_credit_record
    from apps a
    left join credit c on a.applicant_id = c.applicant_id
),
checked as (
    select
        *,
        greatest(app_loaded_at, coalesce(credit_loaded_at, app_loaded_at)) as source_loaded_at,
        array_construct_compact(
            iff(applicant_id is null, 'MISSING_APPLICANT_ID', null),
            iff(loan_amount is null, 'MISSING_LOAN_AMOUNT', iff(loan_amount <= 0, 'INVALID_LOAN_AMOUNT', null)),
            iff(property_value is null, 'MISSING_PROPERTY_VALUE', iff(property_value <= 0, 'INVALID_PROPERTY_VALUE', null)),
            iff(monthly_gross_income is null, 'MISSING_INCOME', iff(monthly_gross_income <= 0, 'INVALID_INCOME', null)),
            iff(has_credit_record and fico_score is null, 'MISSING_CREDIT_SCORE',
                iff(fico_score not between 300 and 850, 'INVALID_CREDIT_SCORE', null)),
            iff(has_credit_record and monthly_debt_obligations is null, 'MISSING_MONTHLY_DEBT',
                iff(monthly_debt_obligations < 0, 'INVALID_MONTHLY_DEBT', null)),
            iff(has_credit_record and (ssn is null or length(ssn) <> 9), 'INVALID_SSN', null),
            iff(not has_credit_record
                and dateadd('hour', {{ var('credit_sla_hours') }}, app_loaded_at) < current_timestamp(),
                'CREDIT_RECORD_NOT_RECEIVED', null)
        ) as validation_errors
    from joined
)
select
    *,
    case
        when array_size(validation_errors) > 0 then 'TECHNICAL_REJECTED'
        when not has_credit_record             then 'PENDING_CREDIT'
        else 'VALIDATED'
    end as processing_status
from checked
