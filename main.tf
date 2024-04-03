terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.84.0"
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
  count                    = length(var.webapp_cidr_range)
  name                     = "webapp-subnet-${count.index + 1}"
  ip_cidr_range            = var.webapp_cidr_range[count.index]
  region                   = var.region
  private_ip_google_access = true
  network                  = google_compute_network.vpc_network.*.name[count.index]
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
  source_ranges      = var.ingress_source_ranges
  target_tags        = var.webapp_tags
}

# resource "google_compute_firewall" "internet_ingress_firewall_allow" {
#   count    = length(var.vpc_names)
#   priority = 100
#   name     = "internet-ingress-firewall-allow-${count.index + 1}"
#   network  = google_compute_network.vpc_network.*.name[count.index]
#   allow {
#     protocol = "tcp"
#     ports    = ["8080"]
#   }
#   destination_ranges = [var.webapp_cidr_range[count.index]]
#   source_ranges = var.ingress_source_ranges
#   target_tags   = var.webapp_tags
# }

resource "google_compute_firewall" "internet_ingress_firewall_allow_hc" {
  count     = length(var.vpc_names)
  priority  = 100
  name      = "internet-ingress-firewall-allow-hc-${count.index + 1}"
  network   = google_compute_network.vpc_network.*.name[count.index]
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = [var.tf_webapp_port]
  }
  destination_ranges = [var.webapp_cidr_range[count.index]]
  # default healthcheck source ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = var.webapp_tags
}

# resource "google_compute_subnetwork" "vpc_subnet_lb_proxy" {
#   name          = "lb-proxy-subnet"
#   ip_cidr_range = "10.129.0.0/23"
#   purpose = "REGIONAL_MANAGED_PROXY"
#   region        = var.region
#   network       = google_compute_network.vpc_network[0].name
#   role = "ACTIVE"
# }

# resource "google_compute_firewall" "internet_ingress_firewall_allow_proxy" {
#   priority = 99
#   name     = "internet-ingress-firewall-allow-proxy"
#   network  = google_compute_network.vpc_network[0].name
#   allow {
#     protocol = "tcp"
#     ports    = ["8080", "443", "80"]
#   }
#   direction     = "INGRESS"
#   destination_ranges = [var.webapp_cidr_range[0]]
#   source_ranges = ["10.129.0.0/23"]
#   target_tags   = var.webapp_tags
# }

resource "google_compute_region_instance_template" "tf_instance_template" {
  project     = var.gcp_project
  region      = var.region
  name        = var.tf_instance_template_name
  description = "This template is used to create webapp instances."

  tags = var.webapp_tags

  labels = {
    environment = "dev"
  }

  instance_description = "Webapp instance created from tf_instance_template"
  machine_type         = var.webapp_machine_type
  can_ip_forward       = false

  # scheduling {
  #   automatic_restart   = true
  #   on_host_maintenance = "MIGRATE"
  # }

  disk {
    source_image = var.webapp_image
    disk_type    = var.webapp_type
    disk_size_gb = var.webapp_size
    auto_delete  = true
    boot         = true
  }
  network_interface {
    network    = google_compute_network.vpc_network[0].name
    subnetwork = google_compute_subnetwork.vpc_subnet_1[0].name

    # access_config {
    #   // Ephemeral public IP
    # }
  }

  metadata = {
    startup-script = <<-EOT
      #!/bin/bash

      cd /home/pkr-gcp-user/webapp
      jq '.HOST = $newHos' --arg newHos '${google_sql_database_instance.cloud_sql_instance.private_ip_address}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
      jq '.PASSWORD = $newPas' --arg newPas '${random_password.cloudsql_password.result}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
      jq '.USER = $newUse' --arg newUse '${google_sql_user.cloudsql_user.name}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
      jq '.DB = $newDb' --arg newDb '${google_sql_database.cloudsql_database.name}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
      jq '.project = $newProj' --arg newProj '${var.gcp_project}'  app/config/gcp.config.json > tmp.$$.json && mv tmp.$$.json app/config/gcp.config.json
      jq '.topic = $newTopic' --arg newTopic '${google_pubsub_topic.tf_topic.name}'  app/config/gcp.config.json > tmp.$$.json && mv tmp.$$.json app/config/gcp.config.json
      sudo systemctl restart csye6225

      EOT
  }
  depends_on = [google_sql_user.cloudsql_user, google_compute_subnetwork.vpc_subnet_1[0], google_compute_global_address.cloudsql_psconnect, google_service_account.tf_service_account, google_pubsub_topic.tf_topic]


  service_account {
    email  = google_service_account.tf_service_account.email
    scopes = ["https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/monitoring.write", "https://www.googleapis.com/auth/pubsub"]
    # scopes = ["cloud-platform"]
  }
}

resource "google_compute_region_autoscaler" "tf_autoscaler" {
  name   = var.tf_autoscaler_name
  region = var.region
  target = google_compute_region_instance_group_manager.tf_instance_group_manager.id

  autoscaling_policy {
    max_replicas    = var.tf_autoscaler_max_replicas
    min_replicas    = var.tf_autoscaler_min_replicas
    cooldown_period = var.tf_autoscaler_cooldown_period

    cpu_utilization {
      target = var.tf_autoscaler_cpu_target
    }
  }

  depends_on = [google_compute_region_instance_group_manager.tf_instance_group_manager]
}

resource "google_compute_health_check" "tf_http_health_check" {
  name        = var.tf_healthcheck_name
  description = "Health check via http"

  timeout_sec         = var.tf_healthcheck_timeout
  check_interval_sec  = var.tf_healthcheck_interval
  healthy_threshold   = var.tf_healthcheck_healthy
  unhealthy_threshold = var.tf_healthcheck_unhealthy

  http_health_check {
    # port_name          = "webapp-port"
    # port_specification = "USE_NAMED_PORT"
    port               = var.tf_webapp_port
    port_specification = var.tf_healthcheck_port_spec
    # host               = "1.2.3.4"
    request_path = var.tf_healthcheck_path
    proxy_header = "NONE"
    # response           = "I AM HEALTHY"
  }

  log_config {
    enable = true
  }
}

resource "google_compute_region_instance_group_manager" "tf_instance_group_manager" {
  name = var.tf_igm_name

  base_instance_name = var.tf_igm_base_name
  region             = var.region
  # distribution_policy_zones  = ["us-central1-a", "us-central1-f"]

  version {
    instance_template = google_compute_region_instance_template.tf_instance_template.id
  }

  # all_instances_config {
  #   metadata = {
  #     metadata_key = "metadata_value"
  #   }
  #   labels = {
  #     label_key = "label_value"
  #   }
  # }

  # target_pools = [google_compute_target_pool.appserver.id]
  # target_size  = 2

  named_port {
    name = var.tf_port_name
    port = var.tf_webapp_port
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.tf_http_health_check.id
    initial_delay_sec = var.tf_autohealing_delay
  }

  depends_on = [google_compute_health_check.tf_http_health_check, google_compute_region_instance_template.tf_instance_template]
}

resource "google_compute_backend_service" "tf_webapp_backend" {
  name                            = var.tf_backend_name
  connection_draining_timeout_sec = 0
  health_checks                   = [google_compute_health_check.tf_http_health_check.id]
  load_balancing_scheme           = var.tf_backend_scheme
  port_name                       = var.tf_port_name
  protocol                        = var.tf_webapp_protocol
  session_affinity                = "NONE"
  timeout_sec                     = var.tf_backend_timeout
  log_config {
    enable = true
  }
  backend {
    group           = google_compute_region_instance_group_manager.tf_instance_group_manager.instance_group
    balancing_mode  = var.tf_backend_mode
    capacity_scaler = var.tf_backend_scale
  }

  depends_on = [google_compute_health_check.tf_http_health_check, google_compute_region_instance_group_manager.tf_instance_group_manager]
}

resource "google_compute_url_map" "http_map" {
  name            = var.tf_map_name
  default_service = google_compute_backend_service.tf_webapp_backend.id
  depends_on      = [google_compute_backend_service.tf_webapp_backend]
}

resource "google_compute_target_https_proxy" "lb_proxy" {
  name    = var.tf_lb_proxy_name
  url_map = google_compute_url_map.http_map.id
  ssl_certificates = [
    google_compute_managed_ssl_certificate.lb_ssl_cert.name
  ]
  depends_on = [google_compute_managed_ssl_certificate.lb_ssl_cert, google_compute_url_map.http_map]
}

resource "google_compute_global_forwarding_rule" "lb_forwarding" {
  name                  = var.tf_lb_forwarding_name
  ip_protocol           = var.tf_webapp_ip_protocol
  load_balancing_scheme = var.tf_lb_forwarding_scheme
  port_range            = var.tf_lb_forwarding_port_range
  target                = google_compute_target_https_proxy.lb_proxy.id
  # ip_address            = google_compute_global_address.default.id

  depends_on = [google_compute_target_https_proxy.lb_proxy]
}

resource "google_compute_managed_ssl_certificate" "lb_ssl_cert" {
  name = var.tf_lb_ssl_cert_name
  managed {
    domains = [var.tf_domain]
  }
}

# resource "google_compute_instance" "tf_instance" {
#   name         = var.webapp_name
#   machine_type = var.webapp_machine_type
#   zone         = var.webapp_zone

#   tags = var.webapp_tags

#   allow_stopping_for_update = true

#   service_account {
#     email  = google_service_account.tf_service_account.email
#     scopes = ["https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/monitoring.write", "https://www.googleapis.com/auth/pubsub"]
#     # scopes = ["cloud-platform"]
#   }
#   boot_disk {
#     initialize_params {
#       image = var.webapp_image
#       type  = var.webapp_type
#       size  = var.webapp_size
#       labels = {
#         # name = "webapp-server"
#         my_label = "value"
#       }
#     }
#   }

#   network_interface {
#     network    = google_compute_network.vpc_network[0].name
#     subnetwork = google_compute_subnetwork.vpc_subnet_1[0].name

#     access_config {
#       // Ephemeral public IP
#     }
#   }
#   metadata = {
#     startup-script = <<-EOT
#       #!/bin/bash

#       cd /home/pkr-gcp-user/webapp
#       jq '.HOST = $newHos' --arg newHos '${google_sql_database_instance.cloud_sql_instance.private_ip_address}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
#       jq '.PASSWORD = $newPas' --arg newPas '${random_password.cloudsql_password.result}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
#       jq '.USER = $newUse' --arg newUse '${google_sql_user.cloudsql_user.name}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
#       jq '.DB = $newDb' --arg newDb '${google_sql_database.cloudsql_database.name}'  app/config/db.config.json > tmp.$$.json && mv tmp.$$.json app/config/db.config.json
#       jq '.project = $newProj' --arg newProj '${var.gcp_project}'  app/config/gcp.config.json > tmp.$$.json && mv tmp.$$.json app/config/gcp.config.json
#       jq '.topic = $newTopic' --arg newTopic '${google_pubsub_topic.tf_topic.name}'  app/config/gcp.config.json > tmp.$$.json && mv tmp.$$.json app/config/gcp.config.json
#       sudo systemctl restart csye6225

#       EOT
#   }
#   depends_on = [google_sql_user.cloudsql_user, google_compute_subnetwork.vpc_subnet_1[0], google_compute_global_address.cloudsql_psconnect, google_service_account.tf_service_account, google_pubsub_topic.tf_topic]
# }

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

  rrdatas = [google_compute_global_forwarding_rule.lb_forwarding.ip_address]

  depends_on = [google_compute_global_forwarding_rule.lb_forwarding]
}

resource "google_service_account" "tf_service_account" {
  account_id   = var.google_service_account
  display_name = "TF GCE Service Account"
}

resource "google_project_iam_binding" "iam_binding_logging" {
  project = var.gcp_project
  role    = "roles/logging.admin"

  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}",
    "serviceAccount:${google_service_account.tf_gcf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_service_account]
}

resource "google_project_iam_binding" "iam_binding_monitoring" {
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"

  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}",
    "serviceAccount:${google_service_account.tf_gcf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_service_account]
}

resource "google_project_iam_binding" "iam_binding_pubsub_p" {
  project = var.gcp_project
  role    = "roles/pubsub.publisher"

  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_service_account]
}

resource "google_project_iam_binding" "iam_binding_pubsub_v" {
  project = var.gcp_project
  role    = "roles/pubsub.viewer"

  members = [
    "serviceAccount:${google_service_account.tf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_service_account]
}

resource "google_pubsub_schema" "tf_schema" {
  name       = var.tf_schema_name
  type       = "AVRO"
  definition = var.tf_schema_definition
}

resource "google_pubsub_topic" "tf_topic" {
  name                       = var.tf_topic_name
  message_retention_duration = var.tf_topic_retention

  depends_on = [google_pubsub_schema.tf_schema]
  schema_settings {
    schema   = "projects/${var.gcp_project}/schemas/${google_pubsub_schema.tf_schema.name}"
    encoding = "JSON"
  }
}

# resource "random_id" "tf_bucket_prefix" {
#   byte_length = 8
# }

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

resource "google_service_account" "tf_gcf_service_account" {
  account_id   = var.tf_gcf_service_account_name
  display_name = "TF Cloud Functions Service Account"
}

resource "google_project_iam_binding" "iam_binding_functions_v" {
  project = var.gcp_project
  role    = "roles/cloudfunctions.viewer"

  members = [
    "serviceAccount:${google_service_account.tf_gcf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_gcf_service_account]
}
resource "google_project_iam_binding" "iam_binding_functions_i" {
  project = var.gcp_project
  role    = "roles/run.invoker"

  members = [
    "serviceAccount:${google_service_account.tf_gcf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_gcf_service_account]
}
resource "google_project_iam_binding" "iam_binding_functions_s" {
  project = var.gcp_project
  role    = "roles/pubsub.subscriber"

  members = [
    "serviceAccount:${google_service_account.tf_gcf_service_account.email}"
  ]
  depends_on = [google_service_account.tf_gcf_service_account]
}

# resource "google_cloudfunctions_function_iam_binding" "binding" {
#   project = var.gcp_project
#   region = var.region
#   cloud_function = google_cloudfunctions2_function.tf_verify_email_cloud_function.name
#   role = "roles/viewer"
#   members = [
#     "serviceAccount:${google_service_account.tf_gcf_service_account.email}"
#   ]
# }

resource "google_cloudfunctions2_function" "tf_verify_email_cloud_function" {
  name        = var.tf_function_name
  location    = var.region
  description = "Cloud Function to verify email for csye6225"

  build_config {
    runtime     = var.tf_function_runtime
    entry_point = var.tf_function_entrypoint
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
    source {
      storage_source {
        bucket = var.tf_serverless_source_bucket
        object = var.tf_serverless_source_object
      }
    }
  }

  service_config {
    max_instance_count = var.tf_function_instance_max
    min_instance_count = var.tf_function_instance_min
    available_memory   = var.tf_function_instance_mem
    available_cpu      = var.tf_function_instance_cpu
    timeout_seconds    = var.tf_function_instance_timeout
    environment_variables = {
      ENV_VAR_TEST    = "config_test"
      cloudDBUser     = google_sql_user.cloudsql_user.name,
      cloudDBPassword = random_password.cloudsql_password.result,
      cloudDBHost     = google_sql_database_instance.cloud_sql_instance.private_ip_address,
      cloudDBDB       = google_sql_database.cloudsql_database.name
    }
    ingress_settings               = var.tf_function_ingress
    all_traffic_on_latest_revision = var.tf_function_all_traffic
    service_account_email          = google_service_account.tf_gcf_service_account.email
    vpc_connector                  = google_vpc_access_connector.tf_vpc_connector.name
    vpc_connector_egress_settings  = var.tf_function_egress
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.tf_topic.id
    retry_policy          = var.tf_function_event_retry
    service_account_email = google_service_account.tf_gcf_service_account.email
  }
  depends_on = [google_sql_user.cloudsql_user, google_compute_subnetwork.vpc_subnet_1[0], google_compute_global_address.cloudsql_psconnect, google_vpc_access_connector.tf_vpc_connector]

}

resource "google_vpc_access_connector" "tf_vpc_connector" {
  name          = var.vpc_connector_name
  ip_cidr_range = var.vpc_connector_cidr
  network       = google_compute_network.vpc_network[0].id
}
