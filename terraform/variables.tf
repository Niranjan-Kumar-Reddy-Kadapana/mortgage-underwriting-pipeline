variable "snowflake_organization_name" { type = string }
variable "snowflake_account_name" { type = string }
variable "snowflake_user" { type = string }
variable "snowflake_private_key_path" { type = string }

variable "environment" {
  type    = string
  default = "dev"
}

variable "data_retention_days" {
  description = "Time Travel window. 90 needs Enterprise edition. Must be >= your audit look-back (30 days)."
  type        = number
  default     = 90
}

variable "transform_warehouse_size" {
  type    = string
  default = "XSMALL"
}

variable "transform_max_clusters" {
  description = "Multi-cluster scale-out for concurrency spikes (Enterprise edition). 1 = off."
  type        = number
  default     = 1
}
