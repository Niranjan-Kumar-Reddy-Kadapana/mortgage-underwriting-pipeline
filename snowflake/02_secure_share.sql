-- Share Gold HMDA data with external auditors. Data is not copied: the auditor queries
-- your storage live and you can revoke instantly. Run as ACCOUNTADMIN (or a role with CREATE SHARE).
-- Replace MORTGAGE_PROD / <AUDITOR_ACCOUNT> as needed.
create share if not exists hmda_auditor_share comment = 'HMDA LAR for federal auditors (read-only)';

grant usage on database MORTGAGE_PROD                         to share hmda_auditor_share;
grant usage on schema   MORTGAGE_PROD.GOLD                    to share hmda_auditor_share;
-- Only SECURE views can be shared. hmda_lar_report is secure and has no SSN or name.
grant select on view    MORTGAGE_PROD.GOLD.HMDA_LAR_REPORT    to share hmda_auditor_share;

alter share hmda_auditor_share add accounts = <AUDITOR_ORG>.<AUDITOR_ACCOUNT>;

-- Auditor has no Snowflake account? Create a managed (reader) account you pay for:
-- create managed account auditor_reader admin_name = 'auditor_admin', admin_password = '<strong>', type = reader;
-- Revoke at any time:  alter share hmda_auditor_share remove accounts = <AUDITOR_ORG>.<AUDITOR_ACCOUNT>;
