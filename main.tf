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
    ports    = ["8080"]
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

  allow_stopping_for_update = true

  service_account {
    email  = google_service_account.tf_service_account.email
    scopes = ["https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/monitoring.write"]
  }
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

      cd /home/pkr-gcp-user/webapp
      jq '.HOST = $newHos' --arg newHos '${google_sql_database_instance.cloud_sql_instance.private_ip_address}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
      jq '.PASSWORD = $newPas' --arg newPas '${random_password.cloudsql_password.result}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
      jq '.USER = $newUse' --arg newUse '${google_sql_user.cloudsql_user.name}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
      jq '.DB = $newDb' --arg newDb '${google_sql_database.cloudsql_database.name}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
      sudo systemctl restart csye6225

      EOT
  }
  # [[ -z $(echo cloudsqlpassword = ${random_password.cloudsql_password.result}, user = ${google_sql_user.cloudsql_user.name}, dbname = ${google_sql_database.cloudsql_database.name} > /test2.txt) ]] || touch failed1.txt
  depends_on = [google_sql_user.cloudsql_user, google_compute_subnetwork.vpc_subnet_1[0], google_compute_global_address.cloudsql_psconnect, google_service_account.tf_service_account]
}

resource "google_compute_global_address" "cloudsql_psconnect" {
  name          = var.cloudsql_psconnect_name
  address_type  = var.cloudsql_psconnect_type
  purpose       = var.cloudsql_psconnect_purpose
  prefix_length = var.cloudsql_psconnect_prefix
  network       = google_compute_network.vpc_network[0].id
}

resource "google_service_networking_connection" "cloudsql_connection" {
  network                 = google_compute_network.vpc_network[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudsql_psconnect.name]
}

resource "google_sql_database_instance" "cloud_sql_instance" {
  name             = var.cloud_sql_instance_name
  region           = var.region
  database_version = var.cloud_sql_version
  depends_on       = [google_service_networking_connection.cloudsql_connection]

  settings {
    tier = var.cloud_sql_instance_tier
    ip_configuration {
      ipv4_enabled    = var.cloud_sql_instance_ipv4_enabled
      private_network = google_compute_network.vpc_network[0].id
      # enable_private_path_for_google_cloud_services = true - if access to bigdata etc reqd
      # allocated_ip_range = 
    }

    availability_type = var.cloud_sql_instance_availability_type
    disk_type         = var.cloud_sql_instance_disk_type
    disk_size         = var.cloud_sql_instance_disk_size
  }
  # set `deletion_protection` to true, will ensure that one cannot accidentally delete this instance by
  # use of Terraform whereas `deletion_protection_enabled` flag protects this instance at the GCP level.
  deletion_protection = false
}

resource "google_sql_database" "cloudsql_database" {
  name            = var.cloudsql_database_name
  instance        = google_sql_database_instance.cloud_sql_instance.name
  deletion_policy = var.google_sql_deletion_policy
  depends_on      = [google_sql_database_instance.cloud_sql_instance]
}

resource "google_sql_user" "cloudsql_user" {
  name            = var.cloudsql_database_user_name
  instance        = google_sql_database_instance.cloud_sql_instance.name
  password        = random_password.cloudsql_password.result
  deletion_policy = var.google_sql_deletion_policy
  depends_on      = [google_sql_database_instance.cloud_sql_instance]
}

resource "random_password" "cloudsql_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_dns_record_set" "webapp" {
  name = var.dns_A_record_name
  type = var.dns_A_record_type
  ttl  = var.dns_A_record_ttl

  managed_zone = var.cloud_dns_managed_zone

  rrdatas = [google_compute_instance.tf_instance.network_interface[0].access_config[0].nat_ip]

  depends_on = [google_compute_instance.tf_instance]
}

resource "google_service_account" "tf_service_account" {
  account_id   = var.google_service_account
  display_name = "TF Service Account"
}

resource "google_project_iam_binding" "iam_binding_logging" {
  project = var.gcp_project
  role    = "roles/logging.admin"

  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_service_account]
}

resource "google_project_iam_binding" "iam_binding_monitoring" {
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"

  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_service_account]
}
