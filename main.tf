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

  allow_stopping_for_update = true

  service_account {
    email  = google_service_account.tf_service_account.email
    # scopes = ["https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/monitoring.write"]
    scopes = ["cloud-platform"]
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
  display_name = "TF GCE Service Account"
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

resource "google_project_iam_binding" "iam_binding_pubsub" {
  project = var.gcp_project
  role    = "roles/pubsub.admin"

  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_service_account]
}

resource "google_pubsub_schema" "tf_schema" {
  name = "tf_schema"
  type = "AVRO"
  definition = "{\n  \"type\" : \"record\",\n  \"name\" : \"Avro\",\n  \"fields\" : [\n    {\n      \"name\" : \"username\",\n      \"type\" : \"string\"\n    }\n  ]\n}\n"
}

resource "google_pubsub_topic" "tf_topic" {
  name = "verify_email"
  message_retention_duration = "604800s"

  depends_on = [google_pubsub_schema.tf_schema]
  schema_settings {
    schema = "projects/${var.gcp_project}/schemas/${google_pubsub_schema.tf_schema.name}"
    encoding = "JSON"
  }
}

# resource "random_id" "tf_bucket_prefix" {
#   byte_length = 8
# }

resource "google_service_account" "tf_gcf_service_account" {
  account_id   = "tf-gcf-service-account"
  display_name = "TF Cloud Function Service Account"
}

# resource "google_storage_bucket" "tf_storage_bucket" {
#   name                        = "${random_id.tf_bucket_prefix.hex}-gcf-source" # Every bucket name must be globally unique
#   location                    = "US"
#   uniform_bucket_level_access = true
# }

# data "archive_file" "tf_serverless_archive" {
#   type        = "zip"
#   output_path = "/tmp/serverless-validate.zip"
#   source_dir  = "serverless-validate/"
# }

# resource "google_storage_bucket_object" "tf_storage_bucket_object" {
#   name   = "serverless-validate.zip"
#   # bucket = google_storage_bucket.tf_storage_bucket.name
#   bucket = "csye6225-validate-email-gcf-source"
#   source = "serverless-validate.zip"
# }

resource "google_cloudfunctions2_function" "tf_verify_email_cloud_function" {
  name        = "verify_email_function"
  location    = "us-east1"
  description = "Cloud Function to verify email for csye6225"

  build_config {
    runtime     = "nodejs20"
    entry_point = "sendValidationEmail" # Set the entry point
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
    source {
      storage_source {
        bucket = "csye6225-validate-email-gcf-source"
        object = "serverless-validate.zip"
      }
    }
  }

  service_config {
    max_instance_count = 1
    min_instance_count = 0
    available_memory   = "256M"
    available_cpu = "1"
    timeout_seconds    = 60
    environment_variables = {
      ENV_VAR_TEST = "config_test"
      cloudDBUser = google_sql_user.cloudsql_user.name,
      cloudDBPassword = random_password.cloudsql_password.result,
      cloudDBHost = google_sql_database_instance.cloud_sql_instance.private_ip_address,
      cloudDBDB = google_sql_database.cloudsql_database.name
    }
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.tf_gcf_service_account.email
    vpc_connector = google_vpc_access_connector.tf_vpc_connector.name
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
  }

  event_trigger {
    trigger_region = "us-east1"
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.tf_topic.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  depends_on = [google_sql_user.cloudsql_user, google_compute_subnetwork.vpc_subnet_1[0], google_compute_global_address.cloudsql_psconnect, google_vpc_access_connector.tf_vpc_connector]

}

resource "google_vpc_access_connector" "tf_vpc_connector" {
  name          = "tf-vpc-connector"
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.vpc_network[0].id
}
