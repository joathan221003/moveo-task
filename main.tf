resource "aws_vpc" "task_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "task_vpc"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Pub Sub
resource "aws_subnet" "Pub_A" {
  vpc_id                  = aws_vpc.task_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "task-Pub-A"
  }
}


#another pub sub for alb
resource "aws_subnet" "Pub_B" {
  vpc_id                  = aws_vpc.task_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "task-Pub-B"
  }
}

#associate sub to RT
resource "aws_route_table_association" "Pub_B_assoc" {
  subnet_id      = aws_subnet.Pub_B.id
  route_table_id = aws_route_table.Pub_RT.id
}

# IGW
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.task_vpc.id

  tags = {
    Name = "task-IGW"
  }
}


#Pub RT
resource "aws_route_table" "Pub_RT" {
  vpc_id = aws_vpc.task_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }

  tags = {
    Name = "task-Pub-RT"
  }
}

#Associate Pub rt to Pub Sub

resource "aws_route_table_association" "Pub_assoc" {
  subnet_id      = aws_subnet.Pub_A.id
  route_table_id = aws_route_table.Pub_RT.id
}


# Priv sub
resource "aws_subnet" "Priv_A" {
  vpc_id            = aws_vpc.task_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "task-Priv-A"
  }
}

#Elastic IP for NAT 
resource "aws_eip" "NAT_EIP" {
  domain = "vpc"

  tags = {
    Name = "task-NAT-EIP"
  }
}


#NAT Gateway (into PUB SUB)
resource "aws_nat_gateway" "NAT" {
  allocation_id = aws_eip.NAT_EIP.id
  subnet_id     = aws_subnet.Pub_A.id

  tags = {
    Name = "task-NAT"
  }

  depends_on = [aws_internet_gateway.IGW]
}

#Private RT

resource "aws_route_table" "Priv_RT" {
  vpc_id = aws_vpc.task_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.NAT.id
  }

  tags = {
    Name = "task-Priv-RT"
  }
}

#Associate Priv RT to Priv SUB

resource "aws_route_table_association" "Priv_assoc" {
  subnet_id      = aws_subnet.Priv_A.id
  route_table_id = aws_route_table.Priv_RT.id
}


#SG for ALB 
resource "aws_security_group" "ALB_SG" {
  name        = "task-ALB-SG"
  description = "Allow HTTP from internet"
  vpc_id      = aws_vpc.task_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "task-ALB-SG"
  }
}

#SG for EC2

resource "aws_security_group" "EC2_SG" {
  name        = "task-EC2-SG"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.task_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.ALB_SG.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task-EC2-SG"
  }
}


data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "task-ec2-SSM-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}


resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "task-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

locals {
  user_data = <<-EOF
        #!/bin/bash
        set -euxo pipefail

        dnf update -y
        dnf install -y docker
        systemctl enable --now docker
        mkdir -p /opt/nginx
        cat > /opt/nginx/index.html <<'HTML'
        yo this is nginx
        HTML
        docker rm -f task-nginx || true
        docker run -d --name task-nginx -p 80:80 \
            -v /opt/nginx/index.html:/usr/share/nginx/html/index.html:ro \
            nginx:latest
    EOF
}

#EC2 creation
resource "aws_instance" "EC2_Nginx" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.Priv_A.id
  vpc_security_group_ids      = [aws_security_group.EC2_SG.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  user_data                   = local.user_data

  tags = {
    Name = "task-Nginx-Priv"
  }
}


#TG 
resource "aws_lb_target_group" "TG" {
  name     = "task-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.task_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "task-TG"
  }
}


#attach tg to ec2
resource "aws_lb_target_group_attachment" "TG_attach" {
  target_group_arn = aws_lb_target_group.TG.arn
  target_id        = aws_instance.EC2_Nginx.id
  port             = 80
}

#alb to pub sub
resource "aws_lb" "ALB" {
  name               = "task-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.ALB_SG.id]
  subnets            = [aws_subnet.Pub_A.id, aws_subnet.Pub_B.id]
  depends_on         = [aws_route_table_association.Pub_assoc, aws_route_table_association.Pub_B_assoc]

  tags = {
    Name = "task-ALB"
  }
}




resource "aws_lb_listener" "HTTP" {
  load_balancer_arn = aws_lb.ALB.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.TG.arn
  }
}



