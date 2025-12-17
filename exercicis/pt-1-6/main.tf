locals {
  owner_name = "Hans Jeremi González Pin"
  owner_slug = "hans-jeremi-gonzalez-pin"
  project    = "asix2opt-cloud-pt1-6"
  common_tags = {
    Owner   = local.owner_name
    Project = local.project
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64*"]
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "vpc-${local.owner_slug}"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "igw-${local.owner_slug}"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = local.azs[0]

  tags = merge(local.common_tags, {
    Name = "subnet-public-${local.owner_slug}"
  })
}

resource "aws_subnet" "private" {
  count             = var.private_instance_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, count.index + 2)
  availability_zone = local.azs[count.index % length(local.azs)]

  tags = merge(local.common_tags, {
    Name = "subnet-private-${count.index + 1}-${local.owner_slug}"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "eip-nat-${local.owner_slug}"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.igw]

  tags = merge(local.common_tags, {
    Name = "nat-${local.owner_slug}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.common_tags, {
    Name = "rt-public-${local.owner_slug}"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(local.common_tags, {
    Name = "rt-private-${local.owner_slug}"
  })
}

resource "aws_route_table_association" "private" {
  count          = var.private_instance_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "bastion" {
  name_prefix = "bastion-${local.owner_slug}-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "sg-bastion-${local.owner_slug}"
  })
}

resource "aws_security_group" "private" {
  name_prefix = "private-${local.owner_slug}-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "sg-private-${local.owner_slug}"
  })
}

resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "private" {
  count     = var.private_instance_count
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "bastion-${local.owner_slug}-${random_id.suffix.hex}"
  public_key = tls_private_key.bastion.public_key_openssh

  tags = merge(local.common_tags, {
    Name = "kp-bastion-${local.owner_slug}"
  })
}

resource "aws_key_pair" "private" {
  count      = var.private_instance_count
  key_name   = "private-${count.index + 1}-${local.owner_slug}-${random_id.suffix.hex}"
  public_key = tls_private_key.private[count.index].public_key_openssh

  tags = merge(local.common_tags, {
    Name = "kp-private-${count.index + 1}-${local.owner_slug}"
  })
}

resource "local_file" "bastion_pem" {
  filename        = "${path.module}/bastion.pem"
  content         = tls_private_key.bastion.private_key_pem
  file_permission = "0400"
}

resource "local_file" "private_pem" {
  count           = var.private_instance_count
  filename        = "${path.module}/private-${count.index + 1}.pem"
  content         = tls_private_key.private[count.index].private_key_pem
  file_permission = "0400"
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = aws_key_pair.bastion.key_name

  tags = merge(local.common_tags, {
    Name = "bastion-${local.owner_slug}"
  })
}

resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "eip-bastion-${local.owner_slug}"
  })
}

resource "aws_eip_association" "bastion" {
  allocation_id = aws_eip.bastion.id
  instance_id   = aws_instance.bastion.id
}

resource "aws_instance" "private" {
  count                       = var.private_instance_count
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private[count.index].id
  vpc_security_group_ids      = [aws_security_group.private.id]
  key_name                    = aws_key_pair.private[count.index].key_name
  associate_public_ip_address = false

  tags = merge(local.common_tags, {
    Name = "private-${count.index + 1}-${local.owner_slug}"
  })
}

resource "aws_s3_bucket" "keys" {
  bucket        = "${local.owner_slug}-pt1-6-${random_id.suffix.hex}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "bucket-keys-${local.owner_slug}"
  })
}

resource "aws_s3_bucket_public_access_block" "keys" {
  bucket                  = aws_s3_bucket.keys.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "keys" {
  bucket = aws_s3_bucket.keys.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_object" "bastion_pub" {
  bucket  = aws_s3_bucket.keys.id
  key     = "bastion.pub"
  content = tls_private_key.bastion.public_key_openssh
}

resource "aws_s3_object" "private_pub" {
  count   = var.private_instance_count
  bucket  = aws_s3_bucket.keys.id
  key     = "private-${count.index + 1}.pub"
  content = tls_private_key.private[count.index].public_key_openssh
}

resource "local_file" "ssh_config" {
  filename = "${path.module}/ssh_config_per_connect.txt"
  content = templatefile("${path.module}/ssh_config.tpl", {
    bastion_ip   = aws_eip.bastion.public_ip
    bastion_user = var.ssh_user
    bastion_key  = "bastion.pem"
    private_ips  = aws_instance.private[*].private_ip
    private_user = var.ssh_user
    private_keys = [for i in range(var.private_instance_count) : "private-${i + 1}.pem"]
  })
}
