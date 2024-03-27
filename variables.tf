variable "gcp_project" {
  type    = string
  default = "csye-6225-project-dev"
}

variable "vpc_names" {
  type    = list(any)
  default = ["tf-network-1", "tf-network-2"]
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "webapp_cidr_range" {
  type    = list(any)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "db_cidr_range" {
  type    = list(any)
  default = ["172.16.0.0/24", "172.16.1.0/24"]
}

variable "route_destination" {
  type    = string
  default = "0.0.0.0/0"
}

variable "vpc_routing_mode" {
  type    = string
  default = "REGIONAL"
}

variable "auto_create_subnetworks" {
  type    = bool
  default = false
}
variable "delete_default_routes_on_create" {
  type    = bool
  default = true
}
variable "firewall" {
  type    = list(any)
  default = ["172.16.0.0/24", "172.16.1.0/24"]
}

variable "webapp_tags" {
  type    = list(any)
  default = ["webapp-server"]
}
variable "webapp_image" {
  type    = string
  default = "csye-6225-image-1711568608"
}
variable "webapp_type" {
  type    = string
  default = "pd-balanced"
}

variable "webapp_size" {
  type    = number
  default = 100
}
variable "webapp_name" {
  type    = string
  default = "tf-instance"
}
variable "webapp_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "webapp_zone" {
  type    = string
  default = "us-east1-b"
}

variable "ingress_source_ranges" {
  type    = list(any)
  default = ["0.0.0.0/0"]

}

variable "route_gateway" {
  type    = string
  default = "default-internet-gateway"
}

variable "cloud_sql_version" {
  type    = string
  default = "POSTGRES_10"
}

variable "cloud_sql_instance_name" {
  type    = string
  default = "private-ip-cloud-sql-instance"
}

variable "cloud_sql_instance_ipv4_enabled" {
  type    = string
  default = false
}

variable "cloud_sql_instance_availability_type" {
  type    = string
  default = "REGIONAL"
}

variable "cloud_sql_instance_disk_type" {
  type    = string
  default = "PD_SSD"
}

variable "cloud_sql_instance_disk_size" {
  type    = number
  default = 100
}

variable "cloudsql_psconnect_name" {
  type    = string
  default = "cloudsql-psconnect"
}

variable "cloudsql_psconnect_type" {
  type    = string
  default = "INTERNAL"
}

variable "cloudsql_psconnect_purpose" {
  type    = string
  default = "VPC_PEERING"
}

variable "cloudsql_psconnect_prefix" {
  type    = number
  default = 16
}

variable "cloud_sql_instance_tier" {
  type    = string
  default = "db-custom-1-3840"
}

variable "cloudsql_database_name" {
  type    = string
  default = "webapp"
}

variable "cloudsql_database_user_name" {
  type    = string
  default = "webapp"
}

variable "google_sql_deletion_policy" {
  type    = string
  default = "ABANDON"
}

variable "dns_A_record_name" {
  type    = string
  default = "abathula.tech."
}

variable "dns_A_record_type" {
  type    = string
  default = "A"
}

variable "dns_A_record_ttl" {
  type    = number
  default = 300
}

variable "cloud_dns_managed_zone" {
  type    = string
  default = "csye-6225-dns-zone"
}

variable "google_service_account" {
  type = string
  default = "tf-service-account"
}

variable "vpc_connector_name" {
  type = string
  default = "tf-vpc-connector"
}

variable "vpc_connector_cidr" {
  type = string
  default = "10.8.0.0/28"
}

variable "tf_schema_name" {
  type = string
  default = "tf_schema"
}

variable "tf_schema_definition" {
  type = string
  default = "{\n  \"type\" : \"record\",\n  \"name\" : \"Avro\",\n  \"fields\" : [\n    {\n      \"name\" : \"username\",\n      \"type\" : \"string\"\n    }\n  ]\n}\n"
}

variable "tf_topic_name" {
  type = string
  default = "verify_email"
}

variable "tf_topic_retention" {
  type = string
  default = "604800s"
}

variable "tf_gcf_service_account_name" {
  type = string
  default = "tf-gcf-service-account"
}

variable "tf_function_name" {
  type = string
  default = "verify_email_function"
}

variable "tf_function_runtime" {
  type = string
  default = "nodejs20"
}

variable "tf_function_entrypoint" {
  type = string
  default = "sendValidationEmail"
}

variable "tf_function_instance_min" {
  type = number
  default = 0
}

variable "tf_function_instance_max" {
  type = number
  default = 1
}
variable "tf_function_instance_mem" {
  type = string
  default = "256M"
}

variable "tf_function_instance_cpu" {
  type = string
  default = "1"
}

variable "tf_function_instance_timeout" {
  type = number
  default = 60
}
variable "tf_function_ingress" {
  type = string
  default = "ALLOW_INTERNAL_ONLY"
}
variable "tf_function_all_traffic" {
  type = bool
  default = true
}
variable "tf_function_egress" {
  type = string
  default = "PRIVATE_RANGES_ONLY"
}
variable "tf_function_event_retry" {
  type = string
  default = "RETRY_POLICY_RETRY"
}
variable "tf_serverless_source_bucket" {
  type = string
  default = "csye6225-validate-email-gcf-source"
}

variable "tf_serverless_source_object" {
  type = string
  default = "serverless-validate.zip"
}
