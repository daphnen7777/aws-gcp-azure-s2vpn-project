provider "aws" {
  region = "ap-northeast-2"
}

resource "aws_vpc" "vpn-test" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  instance_tenancy = "default"
  tags = { Name = "vpn-test" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "pub-sub" {
  vpc_id = aws_vpc.vpn-test.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = { Name = "vpn-test"}
}

resource "aws_internet_gateway" "InGW" {
  vpc_id = aws_vpc.vpn-test.id
  tags = { Name = "InGW" }
}

resource "aws_security_group" "vpn-sg" {
  vpc_id = aws_vpc.vpn-test.id
  name = "vpn-sg"
  description = "testing security group"
  ingress  {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "testing"
  }
  ingress  {
    from_port = -1
    to_port  = -1
    protocol = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "icmp"
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "outbound traffic"
  }
  tags = { Name = "vpn-sg" }
}

resource "aws_route_table" "pub-routing" {
  vpc_id = aws_vpc.vpn-test.id
  route { 
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.InGW.id
  }
  tags = {
    Name = "pub-routing"
  }
}

resource "tls_private_key" "aws_private_keypair" {
  algorithm = "RSA"
  rsa_bits  = 2048
}


resource "aws_key_pair" "aws-ssh-keypair" {
  key_name   = "vpntest"
  public_key = tls_private_key.aws_private_keypair.public_key_openssh

  tags = {
    Name = "vpntest"
  }
}

resource "local_file" "test_private_key" {
  content  = tls_private_key.aws_private_keypair.private_key_pem
  filename = "${path.module}/vpntest.pem"
  file_permission = "0600"
}

locals {
  encoded_private_key = base64encode(local_file.test_private_key.content)
}

resource "aws_instance" "vpn-testing" {
  ami = "ami-042e76978adeb8c48"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.pub-sub.id
  key_name = "vpntest"
  vpc_security_group_ids = [ aws_security_group.vpn-sg.id ]
  tags = { Name = "vpn-testing" }
}

resource "aws_route_table_association" "pub-routetable" {
  subnet_id = aws_subnet.pub-sub.id
  route_table_id = aws_route_table.pub-routing.id
}

#VPN RESOURCES

resource "aws_vpn_gateway" "vgw-for-azrm" {
    vpc_id = aws_vpc.vpn-test.id

    tags = {
        Name = "vgw-for-azrm"
    }
}

resource "aws_vpn_gateway_route_propagation" "testing_route" {
  route_table_id = aws_route_table.pub-routing.id
  vpn_gateway_id = aws_vpn_gateway.vgw-for-azrm.id
}

resource "aws_customer_gateway" "cgw-for-azrm" {
    bgp_asn = 65515
    ip_address = azurerm_public_ip.vpn-public-ip1.ip_address
    type = "ipsec.1"
    tags = {
      Name = "cgw-for-azrm"
    }
}

resource "aws_customer_gateway" "cgw-for-gcp" {
    bgp_asn = 65000
    ip_address = google_compute_ha_vpn_gateway.ha-gateway.vpn_interfaces.1.ip_address
    type = "ipsec.1"
    tags = {
      Name = "cgw-for-gcp"
    }
}

resource "aws_vpn_connection" "aws-azrm-vpn" {
    vpn_gateway_id = aws_vpn_gateway.vgw-for-azrm.id
    customer_gateway_id = aws_customer_gateway.cgw-for-azrm.id
    type = "ipsec.1"
    static_routes_only = false
    local_ipv4_network_cidr = "0.0.0.0/0"
    remote_ipv4_network_cidr = "0.0.0.0/0"
    tunnel1_inside_cidr = "169.254.21.0/30"
    tunnel1_preshared_key = "test123456"
    tunnel2_inside_cidr = "169.254.22.0/30"
    tunnel2_preshared_key = "test123456"
    tags = {
        Name = "aws-azrm-vpn"
    }
}

resource "aws_vpn_connection" "aws-gcp-vpn" {
    vpn_gateway_id = aws_vpn_gateway.vgw-for-azrm.id
    customer_gateway_id = aws_customer_gateway.cgw-for-gcp.id
    type = "ipsec.1"
    static_routes_only = false
    local_ipv4_network_cidr = "0.0.0.0/0"
    remote_ipv4_network_cidr = "0.0.0.0/0"
    tunnel1_ike_versions = ["ikev2"]
    tunnel2_ike_versions = ["ikev2"]
    tags = {
        Name = "aws-gcp-vpn"
    }
}