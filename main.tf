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
  account_id   = "service6225"
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
  priority  = 900

  allow {
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
    email  = google_service_account.service_account.email
    scopes = [
      "https://www.googleapis.com/auth/sqlservice.admin",
      "https://www.googleapis.com/auth/cloud-platform",
      // ... any other required scopes ...
    ]
  }
  tags = ["webapp-server"] # Matches the firewall rule target
  #metadata_startup_script = file("${path.module}/startup-script.sh")
}

output "instance_public_ip" {
  value = google_compute_instance.webapp_instance.network_interface[0].access_config[0].nat_ip
}

resource "google_dns_record_set" "a_record" {
  name         = "saivivekanand.me."
  type         = "A"
  ttl          = 300
  managed_zone = "vivek-dns-zone"
  rrdatas      = [google_compute_instance.webapp_instance.network_interface[0].access_config[0].nat_ip]
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


# Google Cloud Function
/*resource "google_cloudfunctions_function" "cloud_function" {
  name                  = "function-1"
  description           = "A Cloud Function triggered by Pub/Sub to verify email"
  runtime               = "python39"
  available_memory_mb   = 256
  source_archive_bucket = "verify-email-buckets"
  source_archive_object = "function-source.zip"
  entry_point           = "hello_pubsub"

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.pubsub_topic.id
  }

  vpc_connector = google_vpc_access_connector.vpc_connector.id

  # Optional: Set environment variables for the Cloud Function
  environment_variables = {
    MAILGUN_API_KEY = var.mailgun_api_key
    MAILGUN_DOMAIN  = var.mailgun_domain
    MAILGUN_SENDER_EMAIL = var.mailgun_sender_email
    INSTANCE_CONNECTION_NAME = "${var.project_id}:${var.region}:${google_sql_database_instance.mysql_instance.name}"
    DB_HOST_NAME=google_sql_database_instance.mysql_instance.private_ip_address
    DB_USERNAME="webapp"
    DB_PASSWORD=random_password.password.result
    # Any other environment variables can be added here
  }
}*/

/*resource "google_cloudfunctions_function" "cloud_function" {
  name                  = "function-1"
  description           = "A Cloud Function triggered by Pub/Sub to verify email"
  runtime               = "python39"
  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.cloud_function_bucket.name
  source_archive_object = google_storage_bucket_object.cloud_zip.name
  entry_point           = "hello_pubsub"

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.pubsub_topic.id
  }

  vpc_connector = google_vpc_access_connector.vpc_connector.id

  environment_variables = {
    MAILGUN_API_KEY               = var.mailgun_api_key
    MAILGUN_DOMAIN                = var.mailgun_domain
    MAILGUN_SENDER_EMAIL          = var.mailgun_sender_email
    INSTANCE_CONNECTION_NAME      = "${var.project_id}:${var.region}:${google_sql_database_instance.mysql_instance.name}"
    DB_HOST_NAME                  = google_sql_database_instance.mysql_instance.private_ip_address
    DB_USERNAME                   = "webapp"
    DB_PASSWORD                   = random_password.password.result
    GOOGLE_CLOUDFUNCTIONS_GENERATION = "2"
  }
}*/

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