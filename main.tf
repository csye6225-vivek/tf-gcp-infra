provider "google" {
  #credentials = file(var.credentials_file)
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

resource "google_service_account" "service_account" {
  account_id   = var.service_account
  display_name = "Service6225"
}

resource "google_kms_key_ring" "key_ring" {
  name     = "webapp_key_Rings3"
  location = var.region
  /*lifecycle {
    prevent_destroy = false
    ignore_changes  = [name]
  }*/
}

resource "google_project_iam_member" "service_account_kms_binding" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_kms_crypto_key" "vm_key" {
  name            = "vm-key"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = "2592000s" # 30 days
  /*lifecycle {
    prevent_destroy = false
    ignore_changes  = [rotation_period]
  }*/
}

resource "google_kms_crypto_key" "sql_key" {
  name            = "sql-key"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = "2592000s" # 30 days
  /*lifecycle {
    prevent_destroy = false
    ignore_changes  = [rotation_period]
  }*/
}

resource "google_kms_crypto_key" "storage_key" {
  name            = "storage-key"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = "2592000s" # 30 days
  /*lifecycle {
    prevent_destroy = false
    ignore_changes  = [rotation_period]
  }*/
}

resource "google_project_service_identity" "cloudsql_sa" {
  provider = google-beta

  project = var.project_id
  service = "sqladmin.googleapis.com"
}

data "google_storage_project_service_account" "gcs_account" {
}

resource "google_kms_crypto_key_iam_binding" "sql_binding" {
  crypto_key_id = google_kms_crypto_key.sql_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.service_account.email}",
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}",
    "serviceAccount:${google_project_service_identity.cloudsql_sa.email}"
  ]
  depends_on = [
    google_kms_crypto_key.sql_key
  ]

}

resource "google_kms_crypto_key_iam_binding" "vm_binding" {
  crypto_key_id = google_kms_crypto_key.vm_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.service_account.email}",
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}",
    "serviceAccount:${google_project_service_identity.cloudsql_sa.email}",
    "serviceAccount:service-1068004744273@compute-system.iam.gserviceaccount.com"
  ]
  depends_on = [
      google_kms_crypto_key.vm_key
  ]
}

resource "google_kms_crypto_key_iam_binding" "storage_binding" {
  crypto_key_id = google_kms_crypto_key.storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.service_account.email}",
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}",
    "serviceAccount:${google_project_service_identity.cloudsql_sa.email}",
    "serviceAccount:service-1068004744273@gs-project-accounts.iam.gserviceaccount.com"
  ]
  depends_on = [
    google_kms_crypto_key.storage_key
  ]
}



/*resource "google_service_account" "cloudsql_service_account" {
  account_id   = "cloudsql-service-account"
  display_name = "Cloud SQL Service Account"
}

resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloudsql_service_account.email}"
}

resource "google_project_iam_member" "cloudsql_editor" {
  project = var.project_id
  role    = "roles/cloudsql.editor"
  member  = "serviceAccount:${google_service_account.cloudsql_service_account.email}"
} */

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

resource "google_project_iam_member" "kms_admin" {
  project = var.project_id
  role    = "roles/cloudkms.admin"
  member  = "serviceAccount:${google_service_account.service_account.email}"
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

resource "google_project_iam_member" "sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
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
  database_version = "MYSQL_5_7"

  encryption_key_name = google_kms_crypto_key.sql_key.id

  settings {
    tier              = var.instance_tier
    availability_type = "REGIONAL"
    disk_autoresize   = var.disk_autoresize
    disk_size         = 100
    disk_type         = "PD_SSD"

    backup_configuration {
      binary_log_enabled = true
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
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_service_account.service_account
  ]
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
    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.vm_key.id
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.self_link
    subnetwork = google_compute_subnetwork.webapp.self_link
  }

  metadata = {
    startup-script = <<-EOF
    #!/bin/bash

    set -e

    DB_HOSTNAME="${google_sql_database_instance.mysql_instance.private_ip_address}"
    DB_PASSWORD="${random_password.password.result}"

    cat > /opt/.env <<EOF2
    DB_HOSTNAME=$DB_HOSTNAME
    DB_USERNAME=webapp
    DB_PASSWORD=$DB_PASSWORD
    EOF2

    touch /var/run/startup-script-completed
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

/*resource "google_service_account" "storage_service_account" {
  account_id   = "storage-service-account"
  display_name = "Storage Service Account"
} */

resource "google_storage_bucket" "cloud_function_bucket" {
  name          = "verify-email-buckets"
  location      = var.region
  force_destroy = true
  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_key.id
  }
  uniform_bucket_level_access = true
  depends_on = [
    google_service_account.service_account
  ]
}

/*resource "google_storage_bucket_iam_member" "storage_admin" {
  bucket = google_storage_bucket.cloud_function_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.storage_service_account.email}"
}

resource "google_kms_crypto_key_iam_binding" "storage_key_binding" {
  crypto_key_id = google_kms_crypto_key.storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.storage_service_account.email}",
  ]
} */

resource "google_storage_bucket_object" "cloud_zip" {
  name   = var.cloud_zip_name
  bucket = google_storage_bucket.cloud_function_bucket.name
  source = var.cloud_zip_source
}

resource "google_pubsub_topic" "pubsub_topic" {
  name = "verify_email"
}

resource "google_pubsub_subscription" "pubsub_subscription" {
  name  = "verify-email-subscription"
  topic = google_pubsub_topic.pubsub_topic.name

  ack_deadline_seconds = 20
}

resource "google_vpc_access_connector" "vpc_connector" {
  name          = "serverless-connector"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  ip_cidr_range = "10.0.3.0/28"
}

resource "google_cloudfunctions2_function" "cloud_function" {
  name        = "function-1"
  description = "A Cloud Function triggered by Pub/Sub to verify email"
  location    = var.region
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

output "pubsub_topic_name" {
  value = google_pubsub_topic.pubsub_topic.name
}

output "cloud_function_name" {
  value = google_cloudfunctions2_function.cloud_function.name
}