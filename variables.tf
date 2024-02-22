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
