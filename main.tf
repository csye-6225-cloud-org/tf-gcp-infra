terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  # credentials = "/Users/anuraag/.config/gcloud/application_default_credentials.json" 
  credentials = "gcp-creds.json"
  project     = var.gcp_project
  region      = var.region
}

resource "google_compute_network" "vpc_network" {
  count                           = length(var.vpc_names)
  name                            = var.vpc_names[count.index]
  project                         = var.gcp_project
  auto_create_subnetworks         = var.auto_create_subnetworks
  routing_mode                    = var.vpc_routing_mode
  delete_default_routes_on_create = var.delete_default_routes_on_create
}

resource "google_compute_subnetwork" "vpc_subnet_1" {
  count         = length(var.webapp_cidr_range)
  name          = "webapp-subnet-${count.index + 1}"
  ip_cidr_range = var.webapp_cidr_range[count.index]
  region        = var.region
  network       = google_compute_network.vpc_network.*.name[count.index]
}

resource "google_compute_subnetwork" "vpc_subnet_2" {
  count         = length(var.db_cidr_range)
  name          = "db-subnet-${count.index + 1}"
  ip_cidr_range = var.db_cidr_range[count.index]
  region        = var.region
  network       = google_compute_network.vpc_network.*.name[count.index]
}

resource "google_compute_route" "network-route" {
  count            = length(var.vpc_names)
  name             = "internet-route-${count.index + 1}"
  dest_range       = var.route_destination
  network          = google_compute_network.vpc_network.*.name[count.index]
  next_hop_gateway = var.route_gateway
  priority         = 100
}

resource "google_compute_firewall" "internet_ingress_firewall_deny" {
  count    = length(var.vpc_names)
  priority = 101
  name     = "internet-ingress-firewall-deny-${count.index + 1}"
  network  = google_compute_network.vpc_network.*.name[count.index]
  deny {
    protocol = "all"
  }
  destination_ranges = [var.webapp_cidr_range[count.index]]
  # 35.235.240.0/20
  source_ranges = var.ingress_source_ranges
  target_tags   = var.webapp_tags
}

resource "google_compute_firewall" "internet_ingress_firewall_allow" {
  count    = length(var.vpc_names)
  priority = 100
  name     = "internet-ingress-firewall-allow-${count.index + 1}"
  network  = google_compute_network.vpc_network.*.name[count.index]
  allow {
    protocol = "tcp"
    ports    = ["8080", "22"]
  }
  destination_ranges = [var.webapp_cidr_range[count.index]]
  # 35.235.240.0/20
  source_ranges = var.ingress_source_ranges
  target_tags   = var.webapp_tags
}

resource "google_compute_instance" "tf_instance" {
  name         = var.webapp_name
  machine_type = var.webapp_machine_type
  zone         = var.webapp_zone

  tags = var.webapp_tags

  boot_disk {
    initialize_params {
      image = var.webapp_image
      type  = var.webapp_type
      size  = var.webapp_size
      labels = {
        # name = "webapp-server"
        my_label = "value"
      }
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network[0].name
    subnetwork = google_compute_subnetwork.vpc_subnet_1[0].name

    access_config {
      // Ephemeral public IP
    }
  }
    metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      cd /home/pkr-gcp-user
      echo cloudsqlpassword = ${random_password.cloudsql_password.result}, user = ${google_sql_user.cloudsql_user.name}, dbname = ${google_sql_database.cloudsql_database.name} > /test2.txt
      echo host = ${google_compute_global_address.cloudsql_psconnect.address} > /test3.txt
      echo hi > /hitest2.txt
      EOT
  }
  # [[ -z $(echo cloudsqlpassword = ${random_password.cloudsql_password.result}, user = ${google_sql_user.cloudsql_user.name}, dbname = ${google_sql_database.cloudsql_database.name} > /test2.txt) ]] || touch failed1.txt
  depends_on = [google_sql_user.cloudsql_user, google_compute_subnetwork.vpc_subnet_1[0], google_compute_global_address.cloudsql_psconnect]
}

resource "google_compute_global_address" "cloudsql_psconnect" {
  name          = "cloudsql-psconnect"
  address_type  = "INTERNAL"
  purpose       = "VPC_PEERING"
  prefix_length = 16
  network       =  google_compute_network.vpc_network[0].id
  # address       = "100.100.100.105"
}

resource "google_service_networking_connection" "cloudsql_connection" {
  network       =  google_compute_network.vpc_network[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudsql_psconnect.name]
}

resource "google_sql_database_instance" "cloud_sql_instance" {
  name             = "private-ip-cloud-sql-instance"
  region           = var.region
  database_version = "POSTGRES_10"

  depends_on = [google_service_networking_connection.cloudsql_connection]

  settings {
    tier = "db-custom-1-3840"
    ip_configuration {
      ipv4_enabled    = "false"
      private_network = google_compute_network.vpc_network[0].id
      # enable_private_path_for_google_cloud_services = true - if access to bigdata etc reqd
      # allocated_ip_range = 
    }
  }
  # set `deletion_protection` to true, will ensure that one cannot accidentally delete this instance by
  # use of Terraform whereas `deletion_protection_enabled` flag protects this instance at the GCP level.
  deletion_protection = false
}

# resource "google_compute_network_peering_routes_config" "peering_routes_config" {
#   # project = var.gcp_project
#   peering              = google_service_networking_connection.cloudsql_connection.peering
#   # peering = "servicenetworking-googleapis-com"
#   network              = google_compute_network.vpc_network[0].id
#   import_custom_routes = true
#   export_custom_routes = true
#   depends_on = [ google_service_networking_connection.cloudsql_connection ]
# }

resource "google_sql_database" "cloudsql_database" {
  name     = "cloudsql-database"
  instance = google_sql_database_instance.cloud_sql_instance.name
  depends_on = [google_sql_database_instance.cloud_sql_instance]
}

resource "google_sql_user" "cloudsql_user" {
  name     = "cloudsql-user"
  instance = google_sql_database_instance.cloud_sql_instance.name
  password = random_password.cloudsql_password.result
  depends_on = [google_sql_database_instance.cloud_sql_instance]
}

resource "random_password" "cloudsql_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
