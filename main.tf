terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  credentials = "/Users/anuraag/.config/gcloud/application_default_credentials.json"
  # credentials = "gcp-creds.json"
  project = var.gcp_project
  region  = var.region
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
  next_hop_gateway = "default-internet-gateway"
  priority         = 100
}

resource "google_compute_firewall" "internet_ingress_firewall_deny" {
  count = length(var.vpc_names)
  priority = 101
  name    = "internet-ingress-firewall-deny-${count.index + 1}"
  network = google_compute_network.vpc_network.*.name[count.index]
  deny {
    protocol = "all"
  }
  destination_ranges = [var.webapp_cidr_range[count.index]]
  # 35.235.240.0/20
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["webapp-server"]
}

resource "google_compute_firewall" "internet_ingress_firewall_allow" {
  count = length(var.vpc_names)
  priority = 100
  name    = "internet-ingress-firewall-allow-${count.index + 1}"
  network = google_compute_network.vpc_network.*.name[count.index]
  allow {
    protocol = "tcp"
    ports    = ["8080", "22"]
  }
  destination_ranges = [var.webapp_cidr_range[count.index]]
  # 35.235.240.0/20
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["webapp-server"]
}

resource "google_compute_instance" "tf_instance" {
  name         = "tf-instance"
  machine_type = "e2-medium"
  zone  = "us-east1-b"

  tags = ["webapp-server"]

  boot_disk {
    initialize_params {
      image = "packer-1708599626"
      type = "pd-balanced"
      size = 100
      labels = {
        # name = "webapp-server"
        my_label = "value"
      }
    }
  }

  network_interface {
    network = google_compute_network.vpc_network[0].name
    subnetwork = google_compute_subnetwork.vpc_subnet_1[0].name

    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = "echo hi > /test.txt"

}
