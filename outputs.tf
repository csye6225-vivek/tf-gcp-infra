output "vpc_id" {
  value = [for vpc in google_compute_network.vpc : vpc.id]
}

output "webapp_subnet_id" {
  value = [for subnet in google_compute_subnetwork.webapp : subnet.id]
}

output "db_subnet_id" {
  value = [for subnet in google_compute_subnetwork.db : subnet.id]
}
