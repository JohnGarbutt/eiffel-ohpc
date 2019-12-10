provider "openstack" {
  cloud = "cumulus"
}

resource "openstack_compute_instance_v2" "compute" {
  name            = "ohpc-compute-${count.index}"
  image_name      = "CentOS7-1907"
  flavor_name     = "general.v1.tiny"
  key_pair        = "johng"
  security_groups = ["default"]
  count           = 1

  network {
    name = "demo-vxlan"
  }
}

resource "openstack_compute_instance_v2" "login" {
  name            = "ohpc-login"
  image_name      = "CentOS7-1907"
  flavor_name     = "general.v1.tiny"
  key_pair        = "johng"
  security_groups = ["default"]

  network {
    name = "demo-vxlan"
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
    }
}

resource "local_file" "hosts" {
  content  = "${data.template_file.ohpc.rendered}"
  filename = "ohpc_hosts"
}
