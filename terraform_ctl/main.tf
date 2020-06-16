terraform {
  required_version = ">= 0.12, < 0.13"
}

provider "openstack" {
  version = "~> 1.25"
}
provider "local" {
  version = "~> 1.4"
}

resource "openstack_compute_keypair_v2" "terraform" {
  name       = "terraform_${var.instance_prefix}"
  public_key = file("${var.ssh_key_file}.pub")
}


resource "openstack_compute_instance_v2" "control" {
  name = "${var.instance_prefix}-ctl"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.terraform.name}"
  security_groups = ["default"]
  network {
    name = "ilab"
  }

}


output "control-host-ip" {
  value = openstack_compute_instance_v2.control.network[0].fixed_ip_v4
  description = "Public IP for ansible/terraform control host"
}
