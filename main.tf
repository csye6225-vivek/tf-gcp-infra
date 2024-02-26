provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  count                           = var.vpc_count
  name                            = "my-vpc-${count.index}"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
  routing_mode                    = "REGIONAL"
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
  count            = var.vpc_count
  name             = "internet-gateway-${count.index}"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc[count.index].id
  next_hop_gateway = "default-internet-gateway"
}

resource "google_compute_firewall" "allow_application_traffic" {
  count   = var.vpc_count
  name    = "allow-app-traffic-${count.index}"
  network = google_compute_network.vpc[count.index].self_link
  #direction   = "INGRESS"
  #priority    = 1000
  target_tags = ["webapp-server"] # Ensure your instance has this tag

  allow {
    protocol = "tcp"
    ports    = ["8080"] # Replace with your application's port
  }

  source_ranges = ["0.0.0.0/0"] # Allow from any IP
}

resource "google_compute_firewall" "deny_ssh" {
  count     = var.vpc_count
  name      = "deny-ssh-${count.index}"
  network   = google_compute_network.vpc[count.index].self_link
  direction = "INGRESS"
  priority  = 1000

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"] # Deny from any IP
}

/*data "google_compute_image" "webapp_latest" {
  project = var.project_id
  family  = "java-app-fam" # Ensure your Packer images are part of an image family
  most_recent = true
} */

resource "google_compute_instance" "webapp_instance" {
  name         = "webapp-instance"
  machine_type = "n1-standard-1" # Adjust as necessary
  zone         = "us-east1-b"    # Adjust as necessary

  boot_disk {
    initialize_params {
      #image = data.google_compute_image.webapp_latest.self_link
       image = var.image_name
    }
  }

  network_interface {
    network    = google_compute_network.vpc[0].self_link
    subnetwork = google_compute_subnetwork.webapp[0].self_link

    access_config {
      // Ephemeral public IP
    }
  }

  tags = ["webapp-server"] # Matches the firewall rule target
}