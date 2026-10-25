
# variable "aws_region" {
#   description = "AWS region for deployment"
#   type        = string
#   default     = "ap-south-1"
# }

# variable "my_ip_cidr" {
#   description = "Your public IPv4 address followed by /32"
#   type        = string
# }

# variable "key_name" {
#   description = "Existing EC2 key pair name; leave null to use SSM"
#   type        = string
#   default     = null
# }

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

# provider "aws" {
#   region = var.aws_region
# }

# --------------------------------------------------
# 1. Find the latest Amazon Linux 2023 AMI
# --------------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# --------------------------------------------------
# 2. VPC
# --------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "travelmemory-vpc"
  }
}

# --------------------------------------------------
# 3. Public and private subnets
# --------------------------------------------------

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "travelmemory-public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "travelmemory-private-subnet"
  }
}

# --------------------------------------------------
# 4. Internet Gateway
# --------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "travelmemory-igw"
  }
}

# --------------------------------------------------
# 5. Elastic IP and NAT Gateway
# --------------------------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "travelmemory-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "travelmemory-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# --------------------------------------------------
# 6. Public route table and association
# --------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "travelmemory-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------
# 7. Private route table and association
# --------------------------------------------------

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "travelmemory-private-rt"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# --------------------------------------------------
# 8. Web server security group
# --------------------------------------------------

resource "aws_security_group" "web" {
  name        = "travelmemory-web-sg"
  description = "Allow HTTP and SSH from the specified IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from your public IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "travelmemory-web-sg"
  }
}

# --------------------------------------------------
# 9. Database server security group
# --------------------------------------------------


resource "aws_security_group" "database" {
  name        = "travelmemory-mongodb-sg"
  description = "Allow MongoDB access only from the web server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MongoDB from web server only"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "travelmemory-mongodb-sg"
  }
}


# --------------------------------------------------
# 10. IAM role for EC2 Systems Manager
# --------------------------------------------------

resource "aws_iam_role" "ec2_ssm" {
  name = "travelmemory-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "travelmemory-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "travelmemory-ec2-profile"
  role = aws_iam_role.ec2_ssm.name
}

# --------------------------------------------------
# 11. Public web EC2 instance
# --------------------------------------------------

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2.name

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo "<h1>TravelMemory Web Server</h1>" > /var/www/html/index.html
  EOF

  root_block_device {
    encrypted   = true
    volume_size = 16
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm
  ]

  tags = {
    Name = "travelmemory-web-server"
  }
}

# --------------------------------------------------
# 12. Private database EC2 instance
# --------------------------------------------------

resource "aws_instance" "database" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.database.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y mariadb105-server
    systemctl enable --now mariadb
  EOF

  root_block_device {
    encrypted   = true
    volume_size = 16
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm
  ]

  tags = {
    Name = "travelmemory-database-server"
  }
}

# --------------------------------------------------
# 13. Outputs
# --------------------------------------------------

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}

output "database_private_ip" {
  value = aws_instance.database.private_ip
}
