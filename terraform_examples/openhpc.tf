resource "openstack_compute_instance_v2" "testtf" {
  name            = "test-tf-${count.index}"
  image_name      = "CentOS7-OpenHPC"
  flavor_name     = "C6420-Xeon6148-192"
  key_pair        = "usual"
  security_groups = ["default"]
  count           = 1

  network {
    name = "provision-net"
  }
}
