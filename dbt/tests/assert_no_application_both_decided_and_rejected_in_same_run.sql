-- Warn-level sanity check: an application that was technically rejected AND later decided
-- means bureau data arrived after the SLA. It needs a human look (see docs/design_answers.md, 4a).
{{ config(severity='warn', tags=['gold']) }}
select d.application_id
from {{ ref('fct_underwriting_decisions') }} d
join {{ ref('technical_rejections') }} r on r.application_id = d.application_id
