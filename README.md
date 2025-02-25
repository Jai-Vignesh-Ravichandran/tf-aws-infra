
# tf-aws-infra 
This project contains Terraform configurations for provisioning infrastructure on AWS. It defines and manages resources such as compute instances, networking, and other cloud services using Infrastructure as Code (IaC).

## Prerequisites

Before using this Terraform configuration, ensure you have:

- [Terraform](https://developer.hashicorp.com/terraform/downloads) installed (>= v1.0)
- An AWS account with necessary permissions
- AWS CLI installed and configured (`aws configure`)
- Access keys or a configured IAM role for Terraform execution


## Usages

### 1. Initialize Terraform
Run the following command to initialize Terraform and download the required provider plugins:
```sh
terraform init
```

### 2. Validate the Configuration
Check for syntax errors or misconfigurations before applying:
```sh
terraform validate
```

### 3. Plan the Deployment
Preview the changes Terraform will make to your AWS infrastructure:
```sh
terraform plan
```

### 4. Apply the Configuration
Apply the Terraform configuration to provision resources:
```sh
terraform apply -auto-approve
```

### 5. Destroy Resources (Optional)
To remove all created resources and clean up:
```sh
terraform destroy -auto-approve
```

## Variables

This project uses variables defined in `variables.tf`. You can override them using `terraform.tfvars` or CLI arguments:
```sh
terraform apply -var="region=us-east-1"
```

## State Management

Terraform maintains the state file (`terraform.tfstate`) to track managed infrastructure. If using remote state storage, configure it in `backend` settings inside `main.tf`.



