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

# New Load Balancer Security Group (LB SG) - allows HTTP/HTTPS from anywhere
resource "aws_security_group" "lb_sg" {
  name        = "lb-security-group"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.this.id

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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lb-security-group"
  }
}
#Security Group
resource "aws_security_group" "app_sg" {
  name        = "application-security-group"
  description = "Security group for web application EC2 instance"
  vpc_id      = aws_vpc.this.id

  # Allows inbound traffic on specified ports
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }


  # Application port 
  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
    # cidr_blocks = ["0.0.0.0/0"]
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


# Launch Template (replaces the single EC2 instance)
resource "aws_launch_template" "webapp_lt" {
  name_prefix   = "csye6225-asg-"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  #associate_public_ip_address = true

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  user_data = base64encode(<<-EOF
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
  )

  network_interfaces {
    security_groups             = [aws_security_group.app_sg.id]
    associate_public_ip_address = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name             = "webapp-instance"
      AutoScalingGroup = "csye6225-asg"
    }
  }
}

# Auto Scaling Group using the launch template
resource "aws_autoscaling_group" "webapp_asg" {
  name_prefix      = "csye6225-asg-"
  max_size         = 5
  min_size         = 3
  desired_capacity = 3


  launch_template {
    id      = aws_launch_template.webapp_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier = aws_subnet.public[*].id

  # Attach the ALB target group so that instances register automatically
  target_group_arns = [aws_lb_target_group.webapp_tg.arn]

  tag {
    key                 = "AutoScalingGroup"
    value               = "csye6225-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Policies & CloudWatch Alarms

# Scale Up Policy: Increase capacity by 1 when CPU > 12%
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up-policy"
  autoscaling_group_name = aws_autoscaling_group.webapp_asg.name
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
}

# Scale Down Policy: Decrease capacity by 1 when CPU < 8%
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down-policy"
  autoscaling_group_name = aws_autoscaling_group.webapp_asg.name
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
}

# CloudWatch Alarm for CPU High (Scale Up)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 12
  alarm_description   = "Scale up when average CPU > 12%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webapp_asg.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

# CloudWatch Alarm for CPU Low (Scale Down)
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 8
  alarm_description   = "Scale down when average CPU < 8%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webapp_asg.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}

# Application Load Balancer & Route 53    

# Application Load Balancer (ALB)
resource "aws_lb" "app_lb" {
  name               = "csye6225-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "csye6225-app-lb"
  }
}

# Target Group for the Web Application
resource "aws_lb_target_group" "webapp_tg" {
  name     = "csye6225-webapp-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    path                = "/healthz"
    protocol            = "HTTP"
  }

  tags = {
    Name = "csye6225-webapp-tg"
  }
}

# ALB Listener (HTTP)
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webapp_tg.arn
  }
}

# Route 53: Hosted Zone & Alias Record for Root Domain

resource "aws_route53_record" "app_alias" {
  zone_id = var.demo_zone_id
  name    = "demo.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}

