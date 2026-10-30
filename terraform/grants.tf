# Least privilege. Data flows loader -> transformer -> (analyst | compliance).
# Analysts get NO access to BRONZE or STAGING: views run with owner rights and would expose raw SSNs.

locals {
  q = { for s in local.schemas : s => "\"${local.db_name}\".\"${s}\"" }

  warehouse_usage = {
    loader      = { role = snowflake_account_role.loader.name, wh = snowflake_warehouse.loading.name }
    transformer = { role = snowflake_account_role.transformer.name, wh = snowflake_warehouse.transform.name }
    analyst     = { role = snowflake_account_role.analyst.name, wh = snowflake_warehouse.bi.name }
    compliance  = { role = snowflake_account_role.compliance.name, wh = snowflake_warehouse.bi.name }
  }

  roles = {
    loader      = snowflake_account_role.loader.name
    transformer = snowflake_account_role.transformer.name
    analyst     = snowflake_account_role.analyst.name
    compliance  = snowflake_account_role.compliance.name
  }

  schema_privileges = {
    loader_bronze       = { role = "loader", schema = "BRONZE", privs = ["USAGE", "CREATE TABLE", "CREATE STAGE", "CREATE FILE FORMAT", "CREATE PIPE"] }
    transformer_bronze  = { role = "transformer", schema = "BRONZE", privs = ["USAGE"] }
    transformer_staging = { role = "transformer", schema = "STAGING", privs = ["USAGE", "CREATE TABLE", "CREATE VIEW"] }
    transformer_silver  = { role = "transformer", schema = "SILVER", privs = ["USAGE", "CREATE TABLE", "CREATE VIEW"] }
    transformer_gold    = { role = "transformer", schema = "GOLD", privs = ["USAGE", "CREATE TABLE", "CREATE VIEW"] }
    transformer_gov     = { role = "transformer", schema = "GOVERNANCE", privs = ["USAGE"] }
    transformer_audit   = { role = "transformer", schema = "AUDIT", privs = ["USAGE", "CREATE TABLE"] }
    analyst_silver      = { role = "analyst", schema = "SILVER", privs = ["USAGE"] }
    analyst_gold        = { role = "analyst", schema = "GOLD", privs = ["USAGE"] }
    compliance_silver   = { role = "compliance", schema = "SILVER", privs = ["USAGE"] }
    compliance_gold     = { role = "compliance", schema = "GOLD", privs = ["USAGE"] }
    compliance_audit    = { role = "compliance", schema = "AUDIT", privs = ["USAGE"] }
  }

  # SELECT on objects created later (dbt rebuilds tables, so plain grants would vanish).
  future_select = {
    transformer_bronze_tables = { role = "transformer", schema = "BRONZE", type = "TABLES" }
    analyst_silver_tables     = { role = "analyst", schema = "SILVER", type = "TABLES" }
    analyst_gold_tables       = { role = "analyst", schema = "GOLD", type = "TABLES" }
    analyst_gold_views        = { role = "analyst", schema = "GOLD", type = "VIEWS" }
    compliance_silver_tables  = { role = "compliance", schema = "SILVER", type = "TABLES" }
    compliance_gold_tables    = { role = "compliance", schema = "GOLD", type = "TABLES" }
    compliance_gold_views     = { role = "compliance", schema = "GOLD", type = "VIEWS" }
    compliance_audit_tables   = { role = "compliance", schema = "AUDIT", type = "TABLES" }
  }
}

resource "snowflake_grant_privileges_to_account_role" "warehouse_usage" {
  for_each          = local.warehouse_usage
  account_role_name = each.value.role
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = each.value.wh
  }
}

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  for_each          = local.roles
  account_role_name = each.value
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.mortgage.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema" {
  for_each          = local.schema_privileges
  account_role_name = local.roles[each.value.role]
  privileges        = each.value.privs
  on_schema {
    schema_name = local.q[each.value.schema]
  }
  depends_on = [snowflake_schema.layers]
}

resource "snowflake_grant_privileges_to_account_role" "future_select" {
  for_each          = local.future_select
  account_role_name = local.roles[each.value.role]
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = each.value.type
      in_schema          = local.q[each.value.schema]
    }
  }
  depends_on = [snowflake_schema.layers]
}

# dbt attaches masking policies to Silver columns after each build.
resource "snowflake_grant_privileges_to_account_role" "apply_masking" {
  account_role_name = snowflake_account_role.transformer.name
  privileges        = ["APPLY MASKING POLICY"]
  on_account        = true
}

# Roles roll up to SYSADMIN so admins can administer, but SYSADMIN is not COMPLIANCE (no clear-text PII).
resource "snowflake_grant_account_role" "to_sysadmin" {
  for_each         = { for k, v in local.roles : k => v if k != "compliance" }
  role_name        = each.value
  parent_role_name = "SYSADMIN"
}
