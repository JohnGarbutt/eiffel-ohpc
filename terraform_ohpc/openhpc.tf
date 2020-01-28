# By default generates 0-$(min_node-1) compute, else use e.g.
#   terraform apply -var 'nodenames=ohpc-compute-0 ohpc-compute-1 ohpc-compute-2'
# to specify which nodes.
# Note compute instances are for_each members and have IDs like
#	openstack_compute_instance_v2.compute["ohpc-compute-3"]

variable "min_nodes" {
  type = number
  default = 2
  description = "The minimum number of compute nodes (= number of persistent compute nodes) in the cluster"
}

variable "control_host" {
  type = string
  default = "93.186.40.108"
  description = "Public IP address for ansible/terraform control host"
}

variable "nodenames" {
  type = string
  default = ""
  description = "Space-separated list of compute node names - leave empty for only minimum nodes"
}

locals {
  nodeset = var.nodenames != "" ? toset(split(" ", var.nodenames)) : toset([for s in range(var.min_nodes): "ohpc-compute-${s}"])
}

provider "openstack" {
  cloud = "openstack"
}

resource "openstack_compute_instance_v2" "compute" {
  for_each        = local.nodeset
  name            = each.key
  image_name      = "openhpc-centos77"
  # initial:  "CentOS 7.7"
  # snapshot: "openhpc-centos77"
  flavor_name     = "hotdog"
  key_pair        = "centos-at-steveb-control"
  security_groups = ["default"]
  
  network {
    name = "gateway"
  }
}

resource "openstack_compute_instance_v2" "login" {
  name            = "ohpc-login"
  image_name      = "CentOS 7.6"
  flavor_name     = "hotdog"
  key_pair        = "centos-at-steveb-control"
  security_groups = ["default"]
  
  network {
    name = "gateway"
  }
}

resource "openstack_networking_floatingip_v2" "fip_1" {
  pool = "internet"
}

resource "openstack_compute_floatingip_associate_v2" "fip_1" {
  floating_ip = "${openstack_networking_floatingip_v2.fip_1.address}"
  instance_id = "${openstack_compute_instance_v2.login.id}"
}

data  "template_file" "ohpc" {
    template = "${file("./template/ohpc.tpl")}"
    vars = {
      login = <<EOT
${openstack_compute_instance_v2.login.name} ansible_host=${openstack_compute_instance_v2.login.network[0].fixed_ip_v4}
EOT
      computes = <<EOT
%{for compute in openstack_compute_instance_v2.compute}
${compute.name} ansible_host=${compute.network[0].fixed_ip_v4}%{ endfor }
EOT
      fip = "${openstack_networking_floatingip_v2.fip_1.address}"
	  control_host = "${var.control_host}"
    }
    depends_on = [openstack_compute_instance_v2.compute]
}

resource "local_file" "hosts" {
  content  = "${data.template_file.ohpc.rendered}"
  filename = "ohpc_hosts"
}

output "ophc_login_public_ip" {
  value = openstack_networking_floatingip_v2.fip_1.address
  description = "Public IP for OpenHPC login node"
}