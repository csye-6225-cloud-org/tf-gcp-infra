gcp_project       = "csye-6225-gcp-project"
vpc_names         = ["tf-network-1", "tf-network-2"]
region            = "us-east1"
webapp_cidr_range = ["10.0.0.0/24", "10.0.1.0/24"]
db_cidr_range     = ["172.16.0.0/24", "172.16.1.0/24"]
route_destination = "0.0.0.0/0"
