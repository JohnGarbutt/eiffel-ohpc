variable "image" {
  default = "CentOS-7-x86_64-GenericCloud-1907"
}

variable "flavor" {
  default = "C1.vss.small"
}

variable "ssh_key_file" {
  default = "~/.ssh/id_rsa"
}

variable "ssh_user_name" {
  default = "centos"
}

variable "floatingip_pool" {
  default = "CUDN-Internet"
}

variable "instance_prefix" {
  default = "ohpc"
}
