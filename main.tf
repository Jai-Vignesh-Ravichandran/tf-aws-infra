provider "aws" {
  region  = var.aws_region
  profile = "demo"
}

# Creating the VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

# Creating the Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Creating 3 Public Subnets (one in each az)
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-${var.azs[count.index]}"
  }
}

# Creating 3 Private Subnets (one in each az)
resource "aws_subnet" "private" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.vpc_name}-private-${var.azs[count.index]}"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

#  Public route table to allow internet access
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

#  Public Subnet and its Public Route Table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

#  Private Subnet and its Private Route Table
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


#Security Group
resource "aws_security_group" "app_sg" {
  name        = "application-security-group"
  description = "Security group for web application EC2 instance"
  vpc_id      = aws_vpc.this.id

  # Allows inbound traffic on specified ports
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Application port 
  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "application-security-group"
  }
}

#policy for s3
resource "aws_iam_policy" "ec2_s3_policy" {
  name        = "ec2-s3-object-access"
  description = "Allow EC2 to put, get, delete objects in a specific S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ],
        Resource = "${aws_s3_bucket.webapps3.arn}/*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = aws_s3_bucket.webapps3.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

#iamRole

resource "aws_iam_role" "ec2_role" {
  name = "ec2-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance
resource "aws_instance" "webapp" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name

  # Protect against accidental termination
  disable_api_termination = false

  # Root volume configuration
  root_block_device {
    volume_size           = 25
    volume_type           = "gp2"
    delete_on_termination = true
  }

  # Pass PostgreSQL database connection details to the application via user_data
  user_data = <<-EOF
  #!/bin/bash
  # Create .env file with RDS details
  cat <<EOT > /opt/csye6225/webapp/.env
  APP_PORT=${var.app_port}
  NODE_ENV=${var.node_env}
  DB_USERNAME=${var.db_username}
  DB_PASSWORD=${var.db_master_password}
  DB_NAME=${var.db_name}
  DB_HOST=${aws_db_instance.rds.address}
  DB_PORT=${var.db_port}
  TEST_DB_USERNAME=${var.test_db_username}
  TEST_DB_PASSWORD=${var.db_master_password}
  TEST_DB_NAME=${var.test_db_name}
  TEST_DB_HOST=${aws_db_instance.rds.address}
  TEST_DB_PORT=${var.test_db_port}
  AWS_REGION=${var.aws_region}
  S3_BUCKET_NAME=${aws_s3_bucket.webapps3.bucket}
  EOT
  
  INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  sudo sed -i "s/{instance_id}/$INSTANCE_ID/" /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
  systemctl restart myapp.service
EOF


  tags = {
    Name = "webapp-instance"
  }


}

resource "random_uuid" "bucket_suffix" {}

resource "aws_s3_bucket" "webapps3" {
  bucket        = "csye6225-${random_uuid.bucket_suffix.result}"
  force_destroy = true # Enable force destroy to allow Terraform to delete non-empty buckets

  tags = {
    Name = "csye6225-webapps3-bucket"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_sse" {
  bucket = aws_s3_bucket.webapps3.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.bucket_sse_algorithm
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.webapps3.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = var.bucket_Transition_days
      storage_class = "STANDARD_IA"
    }
  }
}
# Output the S3 bucket name
output "webapps3_bucket_name" {
  value = aws_s3_bucket.webapps3.bucket
}

resource "aws_cloudwatch_log_group" "webapp_logs" {
  name              = "WebAppLogs"
  retention_in_days = 7
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


# Database Security Group for RDS 
resource "aws_security_group" "db_sg" {
  name        = "database-security-group"
  description = "Security group for RDS PostgreSQL instances"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Allow PostgreSQL traffic from app security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "database-security-group"
  }
}



# RDS Parameter Group for PostgreSQL
resource "aws_db_parameter_group" "custom" {
  name        = "csye6225-custom-parameter-group"
  family      = "postgres17"
  description = "Custom parameter group for csye6225 PostgreSQL database"

  parameter {
    name         = "max_connections"
    value        = "100"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "password_encryption"
    value = "md5"
  }

  tags = {
    Name = "csye6225-custom-parameter-group"
  }
}


# DB Subnet Group for RDS
resource "aws_db_subnet_group" "this" {
  name       = "csye6225-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "csye6225-db-subnet-group"
  }
}


# RDS Instance 
resource "aws_db_instance" "rds" {
  identifier = "csye6225"
  engine     = "postgres"
  # engine_version          = "17"            
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = var.db_username
  password               = var.db_master_password
  db_name                = var.db_name
  multi_az               = false
  publicly_accessible    = false
  storage_type           = "gp2"
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  parameter_group_name   = aws_db_parameter_group.custom.name
  skip_final_snapshot    = true

  tags = {
    Name = "csye6225-rds-instance"
  }
}

