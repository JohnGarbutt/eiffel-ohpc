# By default generates 0-$(min_node-1) compute, else use e.g.
#   terraform apply -var 'nodenames=ohpc-compute-0 ohpc-compute-1 ohpc-compute-2'
# to specify which nodes.
# Note compute instances are for_each members and have IDs like
#	openstack_compute_instance_v2.compute["ohpc-compute-3"]

variable "nodenames" {
  type = string
  default = ""
  description = "Space-separated list of compute node names - leave empty for only minimum nodes"
}

variable "keypair" {
  type = string
  default = "eiffel-vss-ctl"
  description = "Name of keypair on the ansible/terraform control host"
}

variable "network" {
  type = string
  default = "net1"
}

locals {
  min_nodes = yamldecode(file("../group_vars/all.yml"))["ohpc_partitions"][0]["min_nodes"]
  nodeset = var.nodenames != "" ? toset(split(" ", var.nodenames)) : toset([for s in range(local.min_nodes): "ohpc-compute-${s}"])
  control_host_ip = yamldecode(file("../group_vars/all.yml"))["control_host_ip"]
  compute_image_name = yamldecode(file("../group_vars/all.yml"))["compute_image_name"]
}

provider "openstack" {
  cloud = "vss"
}

resource "openstack_compute_instance_v2" "compute" {
  for_each        = local.nodeset
  name            = each.key
  image_name      = local.compute_image_name
  flavor_name     = "C1.vss.small"
  key_pair        = var.keypair
  security_groups = ["default"]
  
  network {
    name = var.network
  }
}

resource "openstack_compute_instance_v2" "login" {
  name            = "ohpc-login"
  image_name      = "CentOS-7-x86_64-GenericCloud-1907"
  flavor_name     = "C1.vss.small"
  key_pair        = var.keypair
  security_groups = ["default"]
  
  network {
    name = var.network
  }
}

resource "openstack_networking_floatingip_v2" "fip_1" {
  pool = "CUDN-Internet"
}

resource "openstack_compute_floatingip_associate_v2" "fip_1" {
  floating_ip = openstack_networking_floatingip_v2.fip_1.address
  instance_id = openstack_compute_instance_v2.login.id
}

data  "template_file" "ohpc" {
    template = file("./template/ohpc.tpl")
    vars = {
      login = <<EOT
${openstack_compute_instance_v2.login.name} ansible_host=${openstack_compute_instance_v2.login.network[0].fixed_ip_v4}
EOT
      computes = <<EOT
%{for compute in openstack_compute_instance_v2.compute}
${compute.name} ansible_host=${compute.network[0].fixed_ip_v4}%{ endfor }
EOT
      fip = "${openstack_networking_floatingip_v2.fip_1.address}"
	  control_host = "${local.control_host_ip}"
    }
    depends_on = [openstack_compute_instance_v2.compute]
}

resource "local_file" "hosts" {
  content  = data.template_file.ohpc.rendered
  filename = "ohpc_hosts"
}

output "ophc_login_public_ip" {
  value = openstack_networking_floatingip_v2.fip_1.address
  description = "Public IP for OpenHPC login node"
}