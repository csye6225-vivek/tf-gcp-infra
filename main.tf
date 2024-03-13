provider "google" {
  #credentials = file(var.credentials_file)
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

/*provider "random" {
  version = "~> 3.0"
} */

resource "google_compute_network" "vpc_network" {
  name                            = "vpc-${var.environment}"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
  routing_mode                    = "REGIONAL"
}

resource "google_compute_subnetwork" "webapp" {
  name          = "webapp-${var.environment}"
  ip_cidr_range = var.webapp_subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_subnetwork" "db" {
  name          = "db-${var.environment}"
  ip_cidr_range = var.db_subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_route" "internet_gateway" {
  name             = "igw-route-${var.environment}"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc_network.id
  next_hop_gateway = "default-internet-gateway"
}

resource "google_compute_firewall" "allow_application_traffic" {
  name    = "allow-app-traffic-${var.environment}"
  network = google_compute_network.vpc_network.self_link

  allow {
    protocol = "tcp"
    ports    = ["8080"] # Replace with your application's port
  }

  source_ranges = ["0.0.0.0/0"]     # Allow from any IP
  target_tags   = ["webapp-server"] # Ensure your instance has this tag
}

resource "google_compute_firewall" "deny_ssh" {
  name      = "deny-ssh-${var.environment}"
  network   = google_compute_network.vpc_network.self_link
  direction = "INGRESS"
  priority  = 1000

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"] # Deny from any IP
}

resource "google_project_service" "service_networking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_global_address" "private_ip_address" {
  provider      = google-beta
  name          = "mysql-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider                = google-beta
  network                 = google_compute_network.vpc_network.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "mysql_instance" {
  name             = var.instance_name
  database_version = "MYSQL_5_7" # or the version you want to use

  settings {
    tier              = var.instance_tier
    availability_type = "REGIONAL"
    disk_autoresize   = var.disk_autoresize
    disk_size         = 100
    disk_type         = "PD_SSD"

    backup_configuration {
      binary_log_enabled = true // Enable binary logging for HA
      enabled            = var.backup_enabled
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.self_link
    }

    location_preference {
      zone = var.zone
    }
  }

  deletion_protection = false
  depends_on          = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "webapp_db" {
  name     = "webapp"
  instance = google_sql_database_instance.mysql_instance.name
}

resource "random_password" "password" {
  length  = 16
  special = true
}

resource "google_sql_user" "webapp_user" {
  name     = "webapp"
  instance = google_sql_database_instance.mysql_instance.name
  password = random_password.password.result
}

# Assuming you have already defined a CloudSQL instance named `google_sql_database_instance.mysql_instance`

# Create a Google Compute Engine instance with a startup script
/*resource "google_compute_instance" "webapp_instance" {
  name         = "webapp-instance"
  machine_type = "n1-standard-1"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image_name
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = file("${path.module}/startup-script.sh")
} */

# Startup script to configure the web application
resource "google_compute_instance" "webapp_instance" {
  name         = "webapp-instance-${var.environment}"
  machine_type = "n1-standard-1" # Adjust as necessary
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.image_name
    }
  }

  metadata = {
    startup-script = <<-EOT
    #!/bin/bash

    # Exit on any error
    set -e

    # Wait for the Cloud SQL instance to be created and get the private IP address
    DB_HOSTNAME="$(gcloud sql instances describe ${google_sql_database_instance.mysql_instance.name} --format='get(ipAddresses[0].ipAddress)')"

    # Wait for the random password to be generated
    DB_PASSWORD="${random_password.password.result}"

    # Create the .env file with the necessary environment variables
    cat > /opt/.env <<EOF2
    DB_HOSTNAME=$DB_HOSTNAME
    DB_USERNAME=webapp
    DB_PASSWORD=$DB_PASSWORD
    EOF2

    # Signal that the startup script has finished
    touch /var/run/startup-script-completed

    # The rest of your startup script...
    EOT
  }


  network_interface {
    network    = google_compute_network.vpc_network.self_link
    subnetwork = google_compute_subnetwork.webapp.self_link

    access_config {
      // Ephemeral public IP
    }
  }
  service_account {
    scopes = ["cloud-platform"]
  }
  tags = ["webapp-server"] # Matches the firewall rule target
  #metadata_startup_script = file("${path.module}/startup-script.sh")
}
