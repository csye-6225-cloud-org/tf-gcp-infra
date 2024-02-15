terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  credentials = file("/Users/anuraag/.config/gcloud/application_default_credentials.json")
  project     = "csye-6225-gcp-project"
  region      = "us-east1"
}

resource "google_compute_network" "vpc_network" {
  name                            = "terraform-network"
  project                         = "csye-6225-gcp-project"
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "vpc_subnet_1" {
  name          = "webapp"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-east1"
  network       = google_compute_network.vpc_network.name
}

resource "google_compute_subnetwork" "vpc_subnet_2" {
  name          = "db"
  ip_cidr_range = "172.16.0.0/24"
  region        = "us-east1"
  network       = google_compute_network.vpc_network.name
}

resource "google_compute_route" "network-route" {
  name             = "terraform-route"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc_network.name
  next_hop_gateway = "default-internet-gateway"
  priority         = 100
}
