terraform {
  required_version = ">= 0.12, < 0.13"
}

provider "openstack" {
  version = "~> 1.25"
}
provider "local" {
  version = "~> 1.4"
}

data "openstack_networking_network_v2" "internet" {
  name = "${var.floatingip_pool}"
}

resource "openstack_compute_keypair_v2" "terraform" {
  name       = "terraform_${var.instance_prefix}"
  public_key = file("${var.ssh_key_file}.pub")
}

resource "openstack_networking_network_v2" "net1" {
  name           = "net1"
  admin_state_up = "true"
}
resource "openstack_networking_subnet_v2" "net1" {
  name            = "net1"
  network_id      = "${openstack_networking_network_v2.net1.id}"
  cidr            = "192.168.41.0/24"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"] #["131.111.8.42, 131.111.12.20]
  ip_version      = 4
}
resource "openstack_networking_router_v2" "external" {
  name                = "external"
  admin_state_up      = "true"
  external_network_id = "${data.openstack_networking_network_v2.internet.id}"
}
resource "openstack_networking_router_interface_v2" "net1" {
  router_id = "${openstack_networking_router_v2.external.id}"
  subnet_id = "${openstack_networking_subnet_v2.net1.id}"
}

resource "openstack_compute_instance_v2" "control" {
  name = "eiffel-vss-ctl"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    uuid = "${openstack_networking_network_v2.net1.id}"
  }
}

resource "openstack_networking_floatingip_v2" "fip_1" {
  pool = var.floatingip_pool
}
resource "openstack_compute_floatingip_associate_v2" "fip_1" {
  floating_ip = "${openstack_networking_floatingip_v2.fip_1.address}"
  instance_id = "${openstack_compute_instance_v2.control.id}"
}

output "control-host-ip" {
  value = openstack_networking_floatingip_v2.fip_1.address
  description = "Public IP for ansible/terraform control host"
}