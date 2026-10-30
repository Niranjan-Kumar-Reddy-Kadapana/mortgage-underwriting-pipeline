{{ config(materialized='table') }}

-- Denial distribution by reason code. One declined application can carry several reasons, so
-- application_count across reasons can exceed the number of declined applications.
-- primary_reason_count counts each declined application exactly once.
with exploded as (
    select
        d.application_date,
        d.loan_amount,
        f.value::string as reason_code,
        f.index         as reason_rank
    from {{ ref('fct_underwriting_decisions') }} d,
         lateral flatten(input => d.decline_reasons) f
    where d.decision_status = 'DECLINED'
)
select
    date_trunc('month', e.application_date)  as application_month,
    e.reason_code,
    r.description                            as reason_description,
    r.hmda_denial_reason_code,
    count(*)                                 as application_count,
    sum(iff(e.reason_rank = 0, 1, 0))        as primary_reason_count,
    sum(e.loan_amount)                       as total_loan_amount
from exploded e
left join {{ ref('dim_reason_codes') }} r on r.reason_code = e.reason_code
group by 1, 2, 3, 4
