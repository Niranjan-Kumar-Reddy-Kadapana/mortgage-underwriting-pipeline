locals {
  db_name = "MORTGAGE_${upper(var.environment)}"
  schemas = ["BRONZE", "STAGING", "SILVER", "GOLD", "GOVERNANCE", "AUDIT"]
}

# ---------- Database and schemas (Medallion + internal staging + governance + audit) ----------
resource "snowflake_database" "mortgage" {
  name                        = local.db_name
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_schema" "layers" {
  for_each                    = toset(local.schemas)
  database                    = snowflake_database.mortgage.name
  name                        = each.key
  data_retention_time_in_days = var.data_retention_days
}

# ---------- Warehouses: separate compute per workload so loads, dbt and BI never contend ----------
resource "snowflake_warehouse" "loading" {
  name           = "MORTGAGE_LOADING_WH"
  warehouse_size = "XSMALL"
  auto_suspend   = 60
}

resource "snowflake_warehouse" "transform" {
  name              = "MORTGAGE_TRANSFORM_WH"
  warehouse_size    = var.transform_warehouse_size
  auto_suspend      = 60
  min_cluster_count = 1
  max_cluster_count = var.transform_max_clusters
}

resource "snowflake_warehouse" "bi" {
  name           = "MORTGAGE_BI_WH"
  warehouse_size = "XSMALL"
  auto_suspend   = 60
}

# ---------- Roles ----------
resource "snowflake_account_role" "loader" { name = "MORTGAGE_LOADER_ROLE" }
resource "snowflake_account_role" "transformer" { name = "MORTGAGE_TRANSFORMER_ROLE" }
resource "snowflake_account_role" "analyst" { name = "MORTGAGE_ANALYST_ROLE" }
resource "snowflake_account_role" "compliance" { name = "MORTGAGE_COMPLIANCE_OFFICER_ROLE" }

# ---------- Dynamic data masking policies ----------
# Only COMPLIANCE_OFFICER sees clear text. Everyone else, including the dbt role, sees masked values.
# is_role_in_session also honours role inheritance.
resource "snowflake_masking_policy" "mask_ssn" {
  database         = snowflake_database.mortgage.name
  schema           = snowflake_schema.layers["GOVERNANCE"].name
  name             = "MASK_SSN"
  return_data_type = "VARCHAR"
  argument {
    name = "val"
    type = "VARCHAR"
  }
  body = "CASE WHEN IS_ROLE_IN_SESSION('${snowflake_account_role.compliance.name}') THEN val ELSE '***-**-****' END"
}

resource "snowflake_masking_policy" "mask_applicant_name" {
  database         = snowflake_database.mortgage.name
  schema           = snowflake_schema.layers["GOVERNANCE"].name
  name             = "MASK_APPLICANT_NAME"
  return_data_type = "VARCHAR"
  argument {
    name = "val"
    type = "VARCHAR"
  }
  body = "CASE WHEN IS_ROLE_IN_SESSION('${snowflake_account_role.compliance.name}') THEN val ELSE '*** MASKED ***' END"
}
