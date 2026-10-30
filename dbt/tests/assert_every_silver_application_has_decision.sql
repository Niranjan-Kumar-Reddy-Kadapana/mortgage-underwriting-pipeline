{{ config(tags=['gold']) }}
-- Completeness: no validated application may be left without a decision.
select s.application_id
from {{ ref('silver_loan_applications') }} s
left join {{ ref('fct_underwriting_decisions') }} d on d.application_id = s.application_id
where d.application_id is null
