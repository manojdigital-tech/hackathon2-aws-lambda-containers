resource "aws_vpc" "this" {
  count                = var.enable_vpc ? 1 : 0
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  count = var.enable_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
}

resource "aws_subnet" "public" {
  count = var.enable_vpc ? 1 : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = "10.10.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "${local.name_prefix}-public" }
}

resource "aws_subnet" "private" {
  count             = var.enable_vpc ? 2 : 0
  vpc_id            = aws_vpc.this[0].id
  cidr_block        = "10.10.${count.index + 1}.0/24"
  availability_zone = "${var.aws_region}${count.index == 0 ? "a" : "b"}"
  tags = { Name = "${local.name_prefix}-private-${count.index}" }
}

resource "aws_eip" "nat" {
  count = var.enable_vpc ? 1 : 0
  domain = "vpc"
}

resource "aws_nat_gateway" "natgw" {
  count         = var.enable_vpc ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
}

resource "aws_route_table" "public" {
  count  = var.enable_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
}

resource "aws_route" "public_to_inet" {
  count                  = var.enable_vpc ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw[0].id
}

resource "aws_route_table_association" "assoc_public" {
  count          = var.enable_vpc ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count  = var.enable_vpc ? 2 : 0
  vpc_id = aws_vpc.this[0].id
}

resource "aws_route" "private_to_nat" {
  count                  = var.enable_vpc ? 2 : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.natgw[0].id
}

resource "aws_route_table_association" "assoc_private" {
  count          = var.enable_vpc ? 2 : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_security_group" "lambda_sg" {
  count  = var.enable_vpc ? 1 : 0
  name   = "${local.name_prefix}-lambda-sg"
  vpc_id = aws_vpc.this[0].id
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
}
