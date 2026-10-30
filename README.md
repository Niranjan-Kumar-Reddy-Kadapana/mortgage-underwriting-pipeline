# Mortgage Application & Underwriting Pipeline

ELT pipeline on Snowflake: ingests mortgage applications (JSON) and credit bureau records (CSV),
applies automated underwriting rules with dbt, masks PII, and produces HMDA-style compliance reporting.
Medallion architecture (Bronze, Silver, Gold), orchestrated by Airflow, provisioned with Terraform.

## What it does

- **Bronze:** raw landing tables. Loads never fail on bad data.
- **Silver:** joins applications and bureau data, rejects incomplete records to `technical_rejections`, masks SSN and name.
- **Gold:** applies LTV, DTI, FICO and co-signer rules, writes an immutable decision log with reason codes, builds aggregates and an HMDA report (secure view, shareable with auditors).
- **Security:** Dynamic Data Masking + RBAC. Only the compliance role sees SSN and name.
- **Quality:** dbt schema tests, singular tests, and unit tests for every rule boundary.

Architecture diagram: [docs/architecture.md](docs/architecture.md) | Rule logic: [docs/underwriting_logic.md](docs/underwriting_logic.md) | Design answers: [docs/design_answers.md](docs/design_answers.md) | Plan and suggestions: [docs/plan.md](docs/plan.md)

## Repository layout

```
data_simulation/   synthetic data generator + ground-truth expected decisions
ingestion/         PUT + COPY INTO loader (Snowpipe DDL in snowflake/)
snowflake/         Bronze DDL, secure data share, Time Travel audit queries
terraform/         database, schemas, warehouses, roles, grants, masking policies
dbt/               staging -> silver -> gold models, macros, seeds, tests, unit tests
airflow/           DAG, failure alerting, Dockerfile, docker-compose
dashboard/         Streamlit app on Gold aggregates
tests/             pytest boundary tests for the reference rules
.github/workflows/ CI: ruff, pytest, terraform validate, dbt parse
```

## Quick start

Prerequisites: Snowflake account (Enterprise edition or trial, needed for masking policies), Python 3.11+, Terraform 1.5+.

```bash
cp .env.example .env                       # fill in credentials, never commit
pip install -r requirements.txt
pytest -q                                  # rule boundary tests, no Snowflake needed

# 1. Infrastructure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
make tf-plan && (cd terraform && terraform apply)
# then grant the four roles to your users in Snowflake (GRANT ROLE ... TO USER ...)

# 2. Data
make sim                                   # 5k applications, 5% of bureau rows held back as "late"
make init                                  # stage, file formats, Bronze tables
make load

# 3. Transform
cp dbt/profiles.yml.example dbt/profiles.yml
make dbt-empty                             # dry run (also needed for unit tests)
make dbt-all                               # build + test Silver, then Gold

# 4. Late-data demo
make load-late && make dbt-all             # pending applications get decided

# 5. Dashboard and Airflow
make dash
cd airflow && docker compose up --build    # UI on :8080
```

## Push this to GitHub

```bash
git init -b main
git add .
git commit -m "Initial commit: mortgage underwriting pipeline"
# create an empty repo on github.com first (no README), then:
git remote add origin git@github.com:<your-username>/mortgage-underwriting-pipeline.git
git push -u origin main
```

Before pushing, check `git status` shows no `.env`, `*.tfstate`, `terraform.tfvars` or key files (all are in `.gitignore`).

## Key design decisions

1. **Exact rule comparisons.** Limits are tested by cross-multiplication (`loan*100 > 95*value`), not by rounded ratios.
2. **Staging is a hidden schema.** Views run with owner rights, so views over raw SSNs must not be readable by analysts.
3. **Policies in Terraform, attached by dbt.** Table rebuilds drop column policies, so a dbt post-hook re-applies them every run.
4. **Pending is not rejected.** Late bureau data waits inside an SLA window, then self-heals.
5. **Immutable decision log.** Each decision stores its inputs and `rule_version`. Time Travel is the cross-check, not the only evidence.
6. **`+transient: false`.** dbt-snowflake defaults to transient tables, which break the 30-day audit requirement.

## Known limitations

- The SQL, Terraform and DAG were written and reviewed but **not executed against a live Snowflake account** in the authoring environment. Only the Python simulator and rule tests were run. Expect to fix small things on first run (see `terraform validate` and `dbt run --empty`).
- The Terraform provider is pinned to `~> 1.0`. Provider attribute names change between major versions, so adjust if `validate` complains.
- The HMDA report is a simplified mapping, not a filing-ready LAR.
- Bureau data arriving after the SLA leaves a rejection row next to a later decision. A warn-level test flags it; a production version needs a `superseded_at` column.
# mortgage-underwriting-pipeline
