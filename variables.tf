variable "gcp_project" {
  type = string
  default = "csye-6225-gcp-project"
}

variable "vpc_names" {
  type = list(any)
  default = ["tf-network-1", "tf-network-2"]
}

variable "region" {
  type = string
    default = "us-east1"
}

variable "webapp_cidr_range" {
  type = list(any)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "db_cidr_range" {
  type = list(any)
  default = ["172.16.0.0/24", "172.16.1.0/24"]
}

variable "route_destination" {
  type = string
    default = "0.0.0.0/0"
}
