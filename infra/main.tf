# Atalho VPN — servidor WireGuard en AWS EC2 (São Paulo, sa-east-1), dentro del free tier

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { proyecto = var.name }
  }
}

# --- Red: la VPC por defecto, en una zona donde exista el tipo de instancia ---
data "aws_vpc" "default" {
  default = true
}

data "aws_ec2_instance_type_offerings" "vpn" {
  location_type = "availability-zone"
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
  filter {
    name   = "availability-zone"
    values = data.aws_ec2_instance_type_offerings.vpn.locations
  }
}

# --- Imagen: Ubuntu 24.04 oficial de Canonical, de la arquitectura del tipo elegido ---
data "aws_ec2_instance_type" "vpn" {
  instance_type = var.instance_type
}

locals {
  arch = contains(data.aws_ec2_instance_type.vpn.supported_architectures, "arm64") ? "arm64" : "amd64"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${local.arch}-server-*"]
  }
}

# --- Firewall ---
resource "aws_security_group" "vpn" {
  name        = "${var.name}-sg"
  description = "Atalho VPN: WireGuard + SSH"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "wireguard" {
  security_group_id = aws_security_group.vpn.id
  description       = "WireGuard"
  ip_protocol       = "udp"
  from_port         = var.wg_port
  to_port           = var.wg_port
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.vpn.id
  description       = "SSH desde la laptop"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.ssh_cidr
}

# SSH desde el navegador (EC2 Instance Connect) por si cambia la IP de casa
data "aws_ec2_managed_prefix_list" "instance_connect" {
  count = var.ssh_desde_consola ? 1 : 0
  name  = "com.amazonaws.${var.region}.ec2-instance-connect"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_consola" {
  count             = var.ssh_desde_consola ? 1 : 0
  security_group_id = aws_security_group.vpn.id
  description       = "SSH desde la consola de AWS"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  prefix_list_id    = data.aws_ec2_managed_prefix_list.instance_connect[0].id
}

resource "aws_vpc_security_group_egress_rule" "todo" {
  security_group_id = aws_security_group.vpn.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Servidor ---
resource "aws_key_pair" "vpn" {
  key_name   = "${var.name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# La IP fija se crea antes que la instancia para pasársela a install.sh
resource "aws_eip" "vpn" {
  domain = "vpc"
}

resource "aws_instance" "vpn" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.vpn.id]
  key_name                    = aws_key_pair.vpn.key_name
  associate_public_ip_address = true # internet para instalar; luego la reemplaza la IP fija

  # Al primer arranque clona el repo en /opt/atalho-vpn y corre install.sh (reintenta mientras se asocia la IP fija)
  user_data = <<-EOT
    #!/bin/bash
    export WG_PORT=${var.wg_port} ENDPOINT=${aws_eip.vpn.public_ip}
    for i in $(seq 1 20); do
      git clone --depth 1 --branch ${var.repo_branch} ${var.repo_url} /opt/atalho-vpn && break
      rm -rf /opt/atalho-vpn; sleep 10
    done
    bash /opt/atalho-vpn/server/install.sh
  EOT

  # "standard" evita cobros extra por uso alto de CPU (las t3 vienen en "unlimited")
  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8 # el free tier cubre hasta 30 GB
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = var.name }

  # Que una Ubuntu nueva o un cambio en install.sh no recreen el servidor (se perderían los clientes)
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip_association" "vpn" {
  instance_id   = aws_instance.vpn.id
  allocation_id = aws_eip.vpn.id
}

# --- Alerta de gasto: correo apenas haya un cobro real (después de créditos) ---
resource "aws_budgets_budget" "gasto" {
  count        = var.email_alertas == "" ? 0 : 1
  name         = "${var.name}-gasto"
  budget_type  = "COST"
  limit_amount = "1.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 0.01
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.email_alertas]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.email_alertas]
  }
}
