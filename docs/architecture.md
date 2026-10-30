# Architecture

```mermaid
flowchart LR
  subgraph SRC[Sources - simulated]
    A[Mortgage applications<br/>JSON / NDJSON]
    B[Credit bureau<br/>CSV with SSN, FICO, debt]
  end

  subgraph ING[Ingestion]
    S[(Internal stage<br/>encrypted)]
    P[Snowpipe / COPY INTO<br/>idempotent]
  end

  subgraph BRONZE[BRONZE - raw, RBAC locked]
    R1[raw_mortgage_applications<br/>VARIANT]
    R2[raw_credit_bureau<br/>all text]
  end

  subgraph STG[STAGING - internal, no analyst access]
    T1[stg_* views<br/>cast, dedupe]
    T2[int_applications_validated<br/>join + classify]
  end

  subgraph SILVER[SILVER - clean, masked]
    V1[silver_loan_applications<br/>SSN + name MASKED]
    V2[technical_rejections<br/>append-only log]
  end

  subgraph GOLD[GOLD - compliance + BI]
    G0[int_underwriting_rules<br/>LTV, DTI, FICO, co-signer]
    G1[fct_underwriting_decisions<br/>immutable, reason codes]
    G2[agg_decision_summary<br/>agg_denial_reasons]
    G3[hmda_lar_report<br/>SECURE VIEW]
  end

  A --> S
  B --> S
  S --> P --> R1
  P --> R2
  R1 --> T1
  R2 --> T1
  T1 --> T2
  T2 -->|VALIDATED| V1
  T2 -->|TECHNICAL_REJECTED| V2
  T2 -.->|PENDING_CREDIT waits| T2
  V1 --> G0 --> G1
  G1 --> G2
  G1 --> G3
  V2 --> G3
  G2 --> D[Streamlit dashboard]
  G3 -->|Secure Data Share| AU[Federal auditors]

  AF[Airflow DAG<br/>load both -> silver -> gold<br/>alert on failure] -. orchestrates .-> P
  AF -.-> T1
  TF[Terraform<br/>DB, schemas, warehouses, roles, masking policies] -. provisions .-> BRONZE
```

## Layers

| Layer | Schema | Contents | Who can read |
|---|---|---|---|
| Bronze | `BRONZE` | Raw files as received. No casts, so loads never fail on bad data. | loader, transformer |
| Staging | `STAGING` | Typed, de-duplicated views and the join/validation step. Holds raw SSN. | transformer only |
| Silver | `SILVER` | Validated master record + `technical_rejections`. SSN and name carry masking policies. | analyst (masked), compliance (clear) |
| Gold | `GOLD` | Decisions, aggregates, HMDA report. No direct identifiers. | analyst, compliance, auditors (share) |

## Access matrix

| Role | Bronze | Staging | Silver SSN / name | Gold |
|---|---|---|---|---|
| `MORTGAGE_LOADER_ROLE` | write | - | - | - |
| `MORTGAGE_TRANSFORMER_ROLE` | read | write | writes; reads masked | write |
| `MORTGAGE_ANALYST_ROLE` | - | - | masked | read |
| `MORTGAGE_COMPLIANCE_OFFICER_ROLE` | - | - | clear text | read |

## Why STAGING is its own schema
A Snowflake view runs with its owner's privileges. If a view that reads raw Bronze SSNs lived in a
schema analysts can read, the masking policy on Silver would be bypassed. Keeping views over Bronze
in a schema nobody else can see closes that hole.
