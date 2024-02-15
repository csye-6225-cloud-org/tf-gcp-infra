variable "gcp_project" {
  type = string
}

variable "vpc_names" {
  type = list(any)
}

variable "region" {
  type = string
  #   default = "us-east1"
}

variable "webapp_cidr_range" {
  type = list(any)
}

variable "db_cidr_range" {
  type = list(any)
}

variable "route_destination" {
  type = string

}
