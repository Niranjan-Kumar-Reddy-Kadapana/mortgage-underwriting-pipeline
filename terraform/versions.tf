terraform {
  required_version = ">= 1.5"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake" # formerly Snowflake-Labs/snowflake
      version = "~> 1.0"
    }
  }
}

provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  role              = "ACCOUNTADMIN" # bootstrap only; use a dedicated TF role + SECURITYADMIN/SYSADMIN split in prod
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(pathexpand(var.snowflake_private_key_path))
}
