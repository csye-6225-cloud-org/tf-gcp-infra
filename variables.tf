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
  default = "csye-6225-image-1708635565"
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
