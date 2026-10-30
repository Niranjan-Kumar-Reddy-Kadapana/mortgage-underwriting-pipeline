output "database" { value = snowflake_database.mortgage.name }
output "roles" { value = local.roles }
output "warehouses" {
  value = {
    loading   = snowflake_warehouse.loading.name
    transform = snowflake_warehouse.transform.name
    bi        = snowflake_warehouse.bi.name
  }
}
