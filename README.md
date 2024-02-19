# tf-gcp-infra

GCP-Infra
How to start the Project
- terraform init
- terraform fmt
- terraform plan -var-file=dev.tfvars
- terraform apply -var-file=dev.tfvars
- terraform destroy -var-file=dev.tfvars
Project_Details
- Iac of GCP cloud setup
- Creates 1 VPC in the region of our choice
- Creates 2 Subnets
- Creates 1 Internet Gateway
- Creates route tables and associates them with the subnets
Tech_Stack
- Language : HCL
- Framework : Terraform