variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "vpc_name" {
  description = "Name for the VPC"
  type        = string
}

variable "azs" {
  description = "List of Availability Zones where subnets will be created"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for the public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for the private subnets (one per AZ)"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
}

variable "app_port" {
  description = "Port on which the web application runs"
  type        = number
  default     = 8080
}

variable "node_env" {
  description = "Environment for the application"
  type        = string
  default     = "cloud"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "csye6225"
}

variable "db_master_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "csye6225"
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "test_db_username" {
  description = "Test database username"
  type        = string
  default     = "csye6225"
}

variable "test_db_name" {
  description = "Test database name"
  type        = string
  default     = "csye6225_test"
}

variable "test_db_port" {
  description = "Test database port"
  type        = number
  default     = 5432
}

variable "aws_dev_id" {
  description = "Test database port"
  type        = number
  default     = 5432
}

variable "bucket_sse_algorithm" {
  description = "Encription algorithm"
  type        = string
  default     = "AES256"
}

variable "bucket_Transition_days" {
  description = "No of days the bucket holds the resources"
  type        = number
  default     = 30
}

variable "domain_name" {
  description = "Domain name "
  type        = string
  default     = "jaivignesh.me"
}

variable "demo_zone_id" {
  description = "Zone id"
  type        = string
  default     = "null"
}

variable "db_secret_name" {
  description = "Database name"
  type        = string
  default     = "csye622517"
}

variable "demo_certificate_arn" {
  description = "demo certificate"
  type        = string
  default     = "summa"
}



