/*variable "credentials_file" {
  description = "Path to the Google Cloud credentials file"
}*/

variable "project_id" {
  description = "The project ID to host resources in"
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

