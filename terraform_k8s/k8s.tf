provider "openstack" {
  cloud = "eiffel"
}

data "openstack_containerinfra_clustertemplate_v1" "kube14" {
  name = "kubernetes-1.14-2"
}

resource "openstack_containerinfra_cluster_v1" "testk8s" {
  name                 = "testk8s"
  cluster_template_id  = data.openstack_containerinfra_clustertemplate_v1.kube14.id
  master_count         = 1
  node_count           = 1
  keypair              = "default"
}
