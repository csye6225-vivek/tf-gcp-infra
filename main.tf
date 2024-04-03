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

resource "google_service_account" "service_account" {
  account_id   = var.service_account
  display_name = "Service6225"
}

output "service_account_email" {
  value = google_service_account.service_account.email
}

resource "google_project_iam_binding" "logging_admin" {
  project = var.project_id
  role    = "roles/logging.admin"

  members = [
    "serviceAccount:${google_service_account.service_account.email}",
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"

  members = [
    "serviceAccount:${google_service_account.service_account.email}",
  ]
}

resource "google_project_iam_member" "cloud_sql_admin" {
  project = var.project_id
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_compute_network" "vpc_network" {
  name                            = "vpc-${var.environment}"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
  routing_mode                    = "REGIONAL"
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider                = google-beta
  network                 = google_compute_network.vpc_network.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}


resource "google_compute_subnetwork" "webapp" {
  name                     = "webapp-${var.environment}"
  ip_cidr_range            = var.webapp_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc_network.self_link
  private_ip_google_access = true
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

resource "google_compute_firewall" "allow_lb_traffic" {
  name    = "allow-lb-traffic-${var.environment}"
  network = google_compute_network.vpc_network.self_link
  priority = 900

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["webapp-server"]
}

resource "google_compute_firewall" "deny_external_traffic" {
  name    = "deny-external-traffic-${var.environment}"
  network = google_compute_network.vpc_network.self_link

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["webapp-server"]
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

resource "google_compute_instance_template" "webapp_template" {
  name         = "webapp-template-${var.environment}"
  machine_type = "e2-medium"
  region       = var.region

  disk {
    source_image = var.image_name
    auto_delete  = true
    boot         = true
    disk_size_gb = var.vm_disk_size
  }

  network_interface {
    network    = google_compute_network.vpc_network.self_link
    subnetwork = google_compute_subnetwork.webapp.self_link
  }

  #metadata_startup_script = file("${path.module}/startup-script.sh")
  metadata = {
    startup-script = <<-EOF
    #!/bin/bash

    # Exit on any error
    set -e

    # Wait for the Cloud SQL instance to be created and get the private IP address
    DB_HOSTNAME="${google_sql_database_instance.mysql_instance.private_ip_address}"

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
    EOF
  }

  service_account {
    email  = google_service_account.service_account.email
    scopes = [
      "https://www.googleapis.com/auth/sqlservice.admin",
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  tags = ["webapp-server"]
}

resource "google_compute_health_check" "webapp_health_check" {
  name                = "webapp-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10

  http_health_check {
    request_path = "/healthz"
    port         = "8080"
  }
}

resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  name   = "webapp-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.webapp_group_manager.self_link

  autoscaling_policy {
    max_replicas    = 6
    min_replicas    = 3
    cooldown_period = 60

    cpu_utilization {
      target = 0.05
    }
  }
}

resource "google_compute_region_instance_group_manager" "webapp_group_manager" {
  name               = "webapp-group-manager"
  base_instance_name = "webapp-instance"
  region             = var.region

  version {
    instance_template = google_compute_instance_template.webapp_template.id
  }

  named_port {
    name = "http"
    port = 8080
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.webapp_health_check.id
    initial_delay_sec = 300
  }
}

resource "google_compute_global_address" "lb_ip" {
  name = "lb-ip"
}

resource "google_compute_managed_ssl_certificate" "ssl_certificate" {
  name = "ssl-certificate"

  managed {
    domains = ["saivivekanand.me"]
  }
}

resource "google_compute_backend_service" "webapp_backend" {
  name      = "webapp-backend"
  port_name = "http"
  protocol  = "HTTP"

  backend {
    group = google_compute_region_instance_group_manager.webapp_group_manager.instance_group
  }

  health_checks = [google_compute_health_check.webapp_health_check.id]
}

resource "google_compute_url_map" "webapp_url_map" {
  name            = "webapp-url-map"
  default_service = google_compute_backend_service.webapp_backend.id
}

resource "google_compute_target_https_proxy" "webapp_https_proxy" {
  name             = "webapp-https-proxy"
  url_map          = google_compute_url_map.webapp_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_certificate.id]
}

resource "google_compute_global_forwarding_rule" "https_forwarding_rule" {
  name       = "https-forwarding-rule"
  target     = google_compute_target_https_proxy.webapp_https_proxy.id
  port_range = "443"
  load_balancing_scheme = "EXTERNAL"
  ip_address = google_compute_global_address.lb_ip.address
}

resource "google_dns_record_set" "a_record" {
  name         = "saivivekanand.me."
  type         = "A"
  ttl          = 300
  managed_zone = "vivek-dns-zone"
  rrdatas      = [google_compute_global_address.lb_ip.address]
}

# ... [existing resources] ...
# Cloud Storage bucket to store Cloud Function code
 resource "google_storage_bucket" "cloud_function_bucket" {
  name          = "verify-email-buckets"
  location      = var.region
  force_destroy = true
}

resource "google_storage_bucket_object" "cloud_zip" {
  name   = var.cloud_zip_name
  bucket = google_storage_bucket.cloud_function_bucket.name
  source = var.cloud_zip_source #/Users/sai_vivek_vangala/Downloads
}

# Google Cloud Pub/Sub topic to trigger the Cloud Function
resource "google_pubsub_topic" "pubsub_topic" {
  name = "verify_email"
}

resource "google_pubsub_subscription" "pubsub_subscription" {
  name  = "verify-email-subscription"
  topic = google_pubsub_topic.pubsub_topic.name

  ack_deadline_seconds = 20
}


# Serverless VPC Access connector configuration
resource "google_vpc_access_connector" "vpc_connector" {
  name          = "serverless-connector"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  ip_cidr_range = "10.0.3.0/28"
}

resource "google_cloudfunctions2_function" "cloud_function" {
  name                  = "function-1"
  description           = "A Cloud Function triggered by Pub/Sub to verify email"
  location              = var.region
  build_config {
    runtime     = "python310"
    entry_point = "hello_pubsub"
    source {
      storage_source {
        bucket = google_storage_bucket.cloud_function_bucket.name
        object = google_storage_bucket_object.cloud_zip.name
      }
    }
  }
  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    environment_variables = {
      MAILGUN_API_KEY          = var.mailgun_api_key
      MAILGUN_DOMAIN           = var.mailgun_domain
      MAILGUN_SENDER_EMAIL     = var.mailgun_sender_email
      INSTANCE_CONNECTION_NAME = "${var.project_id}:${var.region}:${google_sql_database_instance.mysql_instance.name}"
      DB_HOST_NAME             = google_sql_database_instance.mysql_instance.private_ip_address
      DB_USERNAME              = "webapp"
      DB_PASSWORD              = random_password.password.result
    }
    vpc_connector = google_vpc_access_connector.vpc_connector.id
  }
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.pubsub_topic.id
  }
}

# ... (Other resources like Compute instances, DNS record sets, etc.) ...

# Outputs to display after Terraform apply

output "pubsub_topic_name" {
  value = google_pubsub_topic.pubsub_topic.name
}

output "cloud_function_name" {
  value = google_cloudfunctions2_function.cloud_function.name
}

# ... (Any additional outputs) ...