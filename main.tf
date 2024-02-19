provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  count                   = var.vpc_count
  name                    = "my-vpc-${count.index}"
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "webapp" {
  count         = var.vpc_count
  name          = "webapp-${count.index}"
  ip_cidr_range = "10.0.${count.index * 2 + 1}.0/24"
  region        = var.region
  network       = google_compute_network.vpc[count.index].id
}

resource "google_compute_subnetwork" "db" {
  count         = var.vpc_count
  name          = "db-${count.index}"
  ip_cidr_range = "10.0.${count.index * 2 + 2}.0/24"
  region        = var.region
  network       = google_compute_network.vpc[count.index].id
}

resource "google_compute_route" "internet_gateway" {
  count         = var.vpc_count
  name          = "internet-gateway-${count.index}"
  dest_range    = "0.0.0.0/0"
  network       = google_compute_network.vpc[count.index].id
  next_hop_gateway = "default-internet-gateway"
}
