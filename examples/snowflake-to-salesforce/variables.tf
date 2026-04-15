# ─── TROCCO ─────────────────────────────────────────

variable "trocco_api_key" {
  description = "TROCCO API Key"
  type        = string
  sensitive   = true
}

# ─── Snowflake Source ───────────────────────────────
# モードA: snowflake_src_connection_id を設定 → 既存接続を参照
# モードB: snowflake_src_connection_id を null → host/user/password or private_key で新規作成

variable "snowflake_src_connection_id" {
  description = "Existing TROCCO Snowflake connection ID. If set, skips connection creation."
  type        = number
  default     = null
}

variable "snowflake_src_connection_name" {
  description = "Connection name in TROCCO (used only when creating new connection)"
  type        = string
  default     = "snowflake-src-auto"
}

variable "snowflake_src_host" {
  description = "Snowflake host (used only when creating new connection)"
  type        = string
  default     = ""
}

variable "snowflake_src_user" {
  description = "Snowflake username (used only when creating new connection)"
  type        = string
  default     = ""
}

variable "snowflake_src_auth_method" {
  description = "Snowflake auth method: user_password or key_pair"
  type        = string
  default     = "user_password"

  validation {
    condition     = contains(["user_password", "key_pair"], var.snowflake_src_auth_method)
    error_message = "snowflake_src_auth_method must be 'user_password' or 'key_pair'."
  }
}

variable "snowflake_src_password" {
  description = "Snowflake password (used only when auth_method = user_password)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "snowflake_src_private_key" {
  description = "Snowflake private key (used only when auth_method = key_pair)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "snowflake_src_role" {
  description = "Snowflake role (specify the role created for TROCCO)"
  type        = string
}

variable "snowflake_src_warehouse" {
  description = "Snowflake warehouse name"
  type        = string
}

variable "snowflake_src_database" {
  description = "Snowflake database name"
  type        = string
}

variable "snowflake_src_schema" {
  description = "Snowflake schema name"
  type        = string
  default     = "PUBLIC"
}

variable "snowflake_src_query" {
  description = "SQL query to extract data from Snowflake (e.g. SELECT * FROM my_table)"
  type        = string
}

# ─── Salesforce Destination ─────────────────────────
# モードA: salesforce_dest_connection_id を設定 → 既存接続を参照
# モードB: salesforce_dest_connection_id を null → username/password/security_token で新規作成

variable "salesforce_dest_connection_id" {
  description = "Existing TROCCO Salesforce connection ID. If set, skips connection creation."
  type        = number
  default     = null
}

variable "salesforce_dest_connection_name" {
  description = "Connection name in TROCCO (used only when creating new connection)"
  type        = string
  default     = "salesforce-dest-auto"
}

variable "salesforce_dest_username" {
  description = "Salesforce login username (used only when creating new connection)"
  type        = string
  default     = ""
}

variable "salesforce_dest_password" {
  description = "Salesforce login password (used only when creating new connection)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "salesforce_dest_security_token" {
  description = "Salesforce security token (used only when creating new connection)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "salesforce_dest_auth_end_point" {
  description = "Salesforce auth endpoint (default: https://login.salesforce.com/services/Soap/u/). For Sandbox: https://test.salesforce.com/services/Soap/u/"
  type        = string
  default     = "https://login.salesforce.com/services/Soap/u/"
}

variable "salesforce_dest_object_name" {
  description = "Target Salesforce object name (API name, e.g. Account, Contact)"
  type        = string
}

variable "salesforce_dest_action_type" {
  description = "Action type: insert or upsert"
  type        = string
  default     = "insert"

  validation {
    condition     = contains(["insert", "upsert"], var.salesforce_dest_action_type)
    error_message = "salesforce_dest_action_type must be 'insert' or 'upsert'."
  }
}

variable "salesforce_dest_upsert_key" {
  description = "Upsert key (required when action_type = upsert, External ID field name)"
  type        = string
  default     = null
}

variable "salesforce_dest_api_version" {
  description = "Salesforce API version"
  type        = string
  default     = "55.0"
}

variable "salesforce_dest_ignore_nulls" {
  description = "Ignore NULL values"
  type        = bool
  default     = true
}

variable "salesforce_dest_throw_if_failed" {
  description = "Throw exception on error"
  type        = bool
  default     = false
}

# ─── Job Definition ──────────────────────────────────

variable "job_name" {
  description = "Transfer job name"
  type        = string
}

variable "job_description" {
  description = "Transfer job description"
  type        = string
  default     = "Auto-generated by TROCCO Pipeline Builder"
}

variable "input_columns" {
  description = "Input column definitions (input_option_columns)"
  type = list(object({
    name = string
    type = string
  }))
}

variable "filter_columns" {
  description = "Filter column definitions (source → destination mapping)"
  type = list(object({
    name                = string
    src                 = string
    type                = string
    default             = optional(string, "")
    format              = optional(string)
    json_expand_enabled = optional(bool, false)
  }))
}
