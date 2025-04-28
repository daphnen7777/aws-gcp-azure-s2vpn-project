# Google provider configuration
provider "google" {
    credentials = file("kg-final-project-1b66ab4e796d.json")
    project     = "kg-final-project"
    region      = "asia-northeast3"
}

# GCP compute network
resource "google_compute_network" "vpc_network" {
    name                    = "gcp-vpc"
    auto_create_subnetworks = false
    routing_mode            = "GLOBAL"
}

# GCP subnetwork
resource "google_compute_subnetwork" "gcp-subnet" {
    name           = "gcp-vpc-pub"
    ip_cidr_range  = "30.0.1.0/24"
    region         = "asia-northeast3"
    network        = google_compute_network.vpc_network.id
}

#GCP compute firewall
resource "google_compute_firewall" "allow-internal" {
    name = "icmp-test"
    network = google_compute_network.vpc_network.id
    allow {
        protocol = "icmp"
    }
    source_ranges = [
        "0.0.0.0/0"
    ]
    target_tags = [ "icmp" ]
}

resource "google_compute_firewall" "allow-ssh" {
    name = "ssh-test"
    network = google_compute_network.vpc_network.id
    allow {
        protocol = "tcp"
        ports    = ["22"]
    }
    source_ranges = [
        "0.0.0.0/0"
    ]
    target_tags = ["ssh"]
}

resource "google_compute_instance" "gcp-instance" {
    name         = "nginx-server"
    machine_type = "e2-micro"
    zone         = "asia-northeast3-a"
    tags         = ["ssh", "icmp"]

    boot_disk {
        initialize_params {
            image = "ubuntu-os-cloud/ubuntu-2204-lts"
        }
    }

    network_interface {
        network = google_compute_network.vpc_network.id
        subnetwork = google_compute_subnetwork.gcp-subnet.id
        network_ip = "30.0.1.4"
        access_config {}
    }
}

#GCP VPN RESOURCES
resource "google_compute_router" "router" {
  name = "ha-vpn-router"
  network = google_compute_network.vpc_network.id
  bgp {
    asn = 65000
  }
}

resource "google_compute_ha_vpn_gateway" "ha-gateway" {
  name = "ha-vpn"
  network = google_compute_network.vpc_network.id
}

resource "google_compute_external_vpn_gateway" "peer-gw" {
  name = "peer-gw"
  redundancy_type = "FOUR_IPS_REDUNDANCY"
  interface {
    id = 0
    ip_address = azurerm_public_ip.vpn-public-ip1.ip_address
  }
  interface {
    id = 1
    ip_address = azurerm_public_ip.vpn-public-ip2.ip_address
  }
  interface {
    id = 2
    ip_address = aws_vpn_connection.aws-gcp-vpn.tunnel1_address
  }
  interface {
    id = 3
    ip_address = aws_vpn_connection.aws-gcp-vpn.tunnel2_address
  }
}


resource "google_compute_vpn_tunnel" "tunnel1" {
  name = "az-vpn-tunnel1"
  vpn_gateway = google_compute_ha_vpn_gateway.ha-gateway.id
  peer_external_gateway = google_compute_external_vpn_gateway.peer-gw.id
  peer_external_gateway_interface = 0
  shared_secret = "test123456"
  router = google_compute_router.router.id
  vpn_gateway_interface = 0
  ike_version = 2
}

resource "google_compute_vpn_tunnel" "tunnel2" {
  name = "az-vpn-tunnel2"
  vpn_gateway = google_compute_ha_vpn_gateway.ha-gateway.id
  peer_external_gateway = google_compute_external_vpn_gateway.peer-gw.id
  peer_external_gateway_interface = 1
  shared_secret = "test123456"
  router = "${google_compute_router.router.id}"
  vpn_gateway_interface = 0
  ike_version = 2
}

resource "google_compute_vpn_tunnel" "tunnel3" {
  name = "aws-vpn-tunnel1"
  vpn_gateway = google_compute_ha_vpn_gateway.ha-gateway.id
  peer_external_gateway = google_compute_external_vpn_gateway.peer-gw.id
  peer_external_gateway_interface = 2
  shared_secret = aws_vpn_connection.aws-gcp-vpn.tunnel1_preshared_key
  router = "${google_compute_router.router.id}"
  vpn_gateway_interface = 1
}

resource "google_compute_vpn_tunnel" "tunnel4" {
  name = "aws-vpn-tunnel2"
  vpn_gateway = google_compute_ha_vpn_gateway.ha-gateway.id
  peer_external_gateway = google_compute_external_vpn_gateway.peer-gw.id
  peer_external_gateway_interface = 3
  shared_secret = aws_vpn_connection.aws-gcp-vpn.tunnel2_preshared_key
  router = "${google_compute_router.router.id}"
  vpn_gateway_interface = 1
}

resource "google_compute_router_interface" "router-interface1" {
  name = "router-interface1"
  router = google_compute_router.router.name
  ip_range = "169.254.21.6/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel1.name
}

resource "google_compute_router_peer" "route-peer1" {
  name = "route-peer1"
  router = google_compute_router.router.name
  peer_ip_address = "169.254.21.5"
  peer_asn = 65515
  interface = google_compute_router_interface.router-interface1.name
}

resource "google_compute_router_interface" "router-interface2" {
  name = "router-interface2"
  router = google_compute_router.router.name
  ip_range = "169.254.22.6/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel2.name
}

resource "google_compute_router_peer" "route-peer2" {
  name = "route-peer2"
  router = google_compute_router.router.name
  peer_ip_address = "169.254.22.5"
  peer_asn = 65515
  interface = google_compute_router_interface.router-interface2.name
}

resource "google_compute_router_interface" "router-interface3" {
  name = "route-interface3"
  router = google_compute_router.router.name
  vpn_tunnel = google_compute_vpn_tunnel.tunnel3.name
}

resource "google_compute_router_peer" "route-peer3" {
  name = "route-peer3"
  router = google_compute_router.router.name
  ip_address = aws_vpn_connection.aws-gcp-vpn.tunnel1_cgw_inside_address
  peer_ip_address = aws_vpn_connection.aws-gcp-vpn.tunnel1_vgw_inside_address
  peer_asn = 64512
  interface = google_compute_router_interface.router-interface3.name
}

resource "google_compute_router_interface" "router-interface4" {
  name = "route-interface4"
  router = google_compute_router.router.name
  vpn_tunnel = google_compute_vpn_tunnel.tunnel4.name
}

resource "google_compute_router_peer" "route-peer4" {
  name = "route-peer4"
  router = google_compute_router.router.name
  ip_address = aws_vpn_connection.aws-gcp-vpn.tunnel2_cgw_inside_address
  peer_ip_address = aws_vpn_connection.aws-gcp-vpn.tunnel2_vgw_inside_address
  peer_asn = 64512
  interface = google_compute_router_interface.router-interface4.name
}