# 1. VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-vpc"
  })
}

# 2. Subnets
resource "aws_subnet" "public" {
  count = min(length(var.public_subnet_cidrs), length(data.aws_availability_zones.available.names))
  # count = length(var.public_subnet_cidrs) - Ha dinamikusan egy AZ-be több Subnet mehet

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  # availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-public-subnet-${count.index + 1}"
  })
}

resource "aws_subnet" "private" {
  count = min(length(var.private_subnet_cidrs), length(data.aws_availability_zones.available.names))

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project}-private-subnet-${count.index + 1}"
  })
}

# 3. Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project}-igw"
  })
}

# 4. NAT Gateway & EIP – in one of the public subnets.
resource "aws_eip" "this" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.this.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "${var.project}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

# 5. Route Tables – public (with IGW route) and private (with NAT route).
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-public-route-table"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-private-route-table"
  })
}

# 6. Route Table Associations – associate subnets with the correct route tables.
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# 7. Define Security Groups
resource "aws_security_group" "lb" {
  name        = "${var.project}-sg-lb"
  description = "Load balancer security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-sg-lb"
  })
}

resource "aws_security_group" "bastion" {
  name        = "${var.project}-sg-bastion"
  description = "Bastion host security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH from allowed CIDR"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-sg-bastion"
  })
}

resource "aws_security_group" "application" {
  name        = "${var.project}-sg-application"
  description = "Application security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
    description     = "HTTP from Load Balancer SG"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
    description     = "Inbound SSH from Bastion SG"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-sg-application"
  })
}

resource "aws_security_group" "db" {
  name        = "${var.project}-sg-db"
  description = "Database security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
    description     = "Database port from Application SG"
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL to VPC"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // átírni később S3 Gateway prefix listre
    description = "HTTPS for package updates"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-sg-db"
  })
}

# 8. Define NACLs
resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.this.id

  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    from_port  = 80
    to_port    = 80
    cidr_block = "0.0.0.0/0"
  }

  ingress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    from_port  = 443
    to_port    = 443
    cidr_block = "0.0.0.0/0"
  }

  ingress {
    rule_no    = 120
    action     = "allow"
    protocol   = "tcp"
    from_port  = 22
    to_port    = 22
    cidr_block = var.allowed_ssh_cidr
  }

  ingress {
    rule_no    = 130
    action     = "allow"
    protocol   = "tcp"
    from_port  = 1024
    to_port    = 65535
    cidr_block = "0.0.0.0/0"
  }

  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    from_port  = 0
    to_port    = 0
    cidr_block = "0.0.0.0/0"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-nacl-public"
  })
}

resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.this.id

  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    from_port  = 0
    to_port    = 0
    cidr_block = var.vpc_cidr
  }

  ingress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    from_port  = 1024
    to_port    = 65535
    cidr_block = "0.0.0.0/0"
  }

  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    from_port  = 0
    to_port    = 0
    cidr_block = var.vpc_cidr
  }

  egress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    from_port  = 80
    to_port    = 80
    cidr_block = "0.0.0.0/0"
  }

  egress {
    rule_no    = 120
    action     = "allow"
    protocol   = "tcp"
    from_port  = 443
    to_port    = 443
    cidr_block = "0.0.0.0/0"
  }

  egress {
    rule_no    = 130
    action     = "allow"
    protocol   = "tcp"
    from_port  = 1024
    to_port    = 65535
    cidr_block = "0.0.0.0/0"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-nacl-private"
  })
}

# NACL associations
resource "aws_network_acl_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  network_acl_id = aws_network_acl.public.id
}

resource "aws_network_acl_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  network_acl_id = aws_network_acl.private.id
}

# 9. Define the Bastion Host
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-bastion"
  })
}

# 10. Define the Application Instances
resource "aws_instance" "app" {
  count = length(aws_subnet.private)

  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private[count.index].id
  vpc_security_group_ids      = [aws_security_group.application.id]
  key_name                    = var.key_name
  associate_public_ip_address = false

  user_data = file("${path.module}/userdata.sh")

  tags = merge(local.common_tags, {
    Name = "${var.project}-app-${count.index + 1}"
  })
}

# 11. Define the Load Balancer
resource "aws_lb" "this" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${var.project}-alb"
  })
}

# Define the Target Group
resource "aws_lb_target_group" "app" {
  name     = "${var.project}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-tg"
  })
}

# Define the Target Group Attachment
resource "aws_lb_target_group_attachment" "app" {
  count = length(aws_instance.app)

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app[count.index].id
  port             = 80
}

# Define the Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# 12. (Optional) Define the Database