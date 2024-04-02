/*variable "credentials_file" {
  description = "Path to the Google Cloud credentials file"
}*/

variable "project_id" {
  description = "The project ID to host resources in"
}

variable "mailgun_api_key" {
  description = "The project ID to host resources in"
  type = string
  default = "e8c7879c2e58663c7838fe4a37e39d08-f68a26c9-98005b1a"
}

variable "mailgun_domain" {
  description = "The project ID to host resources in"
  type = string
  default = "mail.saivivekanand.me"
}

variable "mailgun_sender_email" {
  description = "The project ID to host resources in"
  type = string
  default = "postmaster@mail.saivivekanand.me"
}

variable "cloud_zip_source" {
  description = "The project ID to host resources in"
  type = string
  default = "/Users/sai_vivek_vangala/Downloads/function-source.zip"
}

variable "cloud_zip_name" {
  description = "The project ID to host resources in"
  type = string
  default = "function-source.zip"
}

variable "db_hostname" {
  description = "The project ID to host resources in"
  type = string
  default = "10.0.1.0"
}

variable "db_username" {
  description = "The project ID to host resources in"
  type = string
  default = "webapp"
}

variable "db_password" {
  description = "The project ID to host resources in"
  type = string
  default = "Mnblkjpoi@123"
}

variable "region" {
  description = "The region where resources will be created"
}

variable "environment" {
  description = "A unique name for the environment"
}

variable "webapp_subnet_cidr" {
  description = "The CIDR block for the webapp subnet"
}

variable "db_subnet_cidr" {
  description = "The CIDR block for the db subnet"
}

variable "image_name" {
  description = "Name of the custom image"
}

variable "zone" {
  description = "Name of the zone"
}

variable "instance_name" {
  description = "The name of the CloudSQL instance"
  type        = string
  default     = "my-mysql-instance"
}

variable "instance_tier" {
  description = "The machine type for the CloudSQL instance"
  type        = string
  default     = "db-n1-standard-1"
}

variable "disk_autoresize" {
  description = "Configuration to auto-resize the disk"
  type        = bool
  default     = true
}

variable "backup_enabled" {
  description = "Whether backups are enabled for the CloudSQL instance"
  type        = bool
  default     = true
}

/*variable "private_network" {
  description = "The self link of the VPC for the CloudSQL instance"
  type        = string
  // This should be the actual self_link of your custom VPC
  default     = "projects/my-project/global/networks/vpc-dev"
}*/

