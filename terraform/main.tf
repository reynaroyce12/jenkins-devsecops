terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.36"
    }
  }

  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

variable "region" {
  description = "AWS region for the demo."
  type        = string
  default     = "us-east-1"
}

variable "subnet_id" {
  description = "Public subnet with an internet route for package downloads, Docker Hub, and Systems Manager."
  type        = string
}

provider "aws" {
  region = var.region
}

data "aws_subnet" "app" {
  id = var.subnet_id
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-arm64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_security_group" "app" {
  name_prefix = "textbook-library-"
  description = "Outbound access for the Textbook Library demo"
  vpc_id      = data.aws_subnet.app.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "app" {
  name_prefix = "textbook-library-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "textbook-library-"
  role        = aws_iam_role.app.name
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t4g.small"
  subnet_id                   = data.aws_subnet.app.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted   = true
    volume_size = 16
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/bootstrap.sh.tftpl", {
    deploy_script = filebase64("${path.module}/deploy-instance.sh")
    seed_data     = filebase64("${path.module}/../data/textbooks_data.json")
  })
  user_data_replace_on_change = true

  tags = {
    Name = "textbook-library-demo"
  }

  depends_on = [aws_iam_role_policy_attachment.ssm]
}

output "instance_id" {
  value = aws_instance.app.id
}
