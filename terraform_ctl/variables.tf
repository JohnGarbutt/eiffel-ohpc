variable "image" {
  default = "CentOS7.8"
}

variable "flavor" {
  default = "general.v1.tiny"
}

variable "ssh_key_file" {
  default = "~/.ssh/id_rsa"
}

variable "ssh_user_name" {
  default = "centos"
}

variable "floatingip_pool" {
  default = ""
}

variable "instance_prefix" {
  default = "jg-ohpc"
}
