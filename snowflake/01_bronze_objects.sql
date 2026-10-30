-- Run as MORTGAGE_LOADER_ROLE (python ingestion/load_bronze.py --init). Schemas come from Terraform.
create file format if not exists bronze.ff_json type = json strip_outer_array = false;

create file format if not exists bronze.ff_csv
    type = csv skip_header = 1 field_optionally_enclosed_by = '"'
    null_if = ('', 'NULL', 'null') empty_field_as_null = true;

-- Internal stage: encrypted at rest by default (SNOWFLAKE_FULL).
create stage if not exists bronze.raw_stage;

-- Bronze keeps data exactly as received. Everything except the JSON is text, so a bad value
-- can never fail a load. Casting and validation happen in dbt, where rejects are logged.
create table if not exists bronze.raw_mortgage_applications (
    raw          variant,
    _source_file string,
    _loaded_at   timestamp_ltz default current_timestamp()
);

create table if not exists bronze.raw_credit_bureau (
    applicant_id string,
    ssn          string,
    fico_score   string,
    monthly_debt string,
    report_date  string,
    _source_file string,
    _loaded_at   timestamp_ltz default current_timestamp()
);

-- Production: continuous load with Snowpipe from cloud storage (needs a storage integration).
-- create stage bronze.ext_stage url = 's3://<bucket>/mortgage/' storage_integration = <int>;
-- create pipe bronze.pipe_applications auto_ingest = true as
--   copy into bronze.raw_mortgage_applications (raw, _source_file)
--   from (select $1, metadata$filename from @bronze.ext_stage/applications/)
--   file_format = (format_name = 'bronze.ff_json');
-- create pipe bronze.pipe_credit_bureau auto_ingest = true as
--   copy into bronze.raw_credit_bureau (applicant_id, ssn, fico_score, monthly_debt, report_date, _source_file)
--   from (select $1, $2, $3, $4, $5, metadata$filename from @bronze.ext_stage/credit/)
--   file_format = (format_name = 'bronze.ff_csv');
