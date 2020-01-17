# Notes:
# - define azure credentials by sourcing azcreds.sh
# - TODO: take ssh key from openstack or a pub key on this node

# By default generates 0-$(min_node-1) compute, else use e.g.
#   terraform apply -var 'nodenames=ohpc-compute-0 ohpc-compute-1 ohpc-compute-2'
# to specify which nodes.
# Note compute instances are for_each members and have IDs like
#	azurerm_virtual_machine.compute["ohpc-compute-3"]

provider "azurerm" {
}

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

# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "myterraformgroup" {
    name     = "openhpc"
    location = "eastus"
}

# Create virtual network
resource "azurerm_virtual_network" "myterraformnetwork" {
    name                = "openhpc-vnet"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = azurerm_resource_group.myterraformgroup.name
}

# Create subnet
resource "azurerm_subnet" "myterraformsubnet" {
    name                 = "openhpc-subnet"
    resource_group_name  = azurerm_resource_group.myterraformgroup.name
    virtual_network_name = azurerm_virtual_network.myterraformnetwork.name
    address_prefix       = "10.0.1.0/24"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "myterraformnsg" {
    name                = "openhpc-nsg"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.myterraformgroup.name
    
    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

# Create network interface for login
resource "azurerm_network_interface" "login_nic" {
    name                      = "login-nic"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.myterraformgroup.name
    network_security_group_id = azurerm_network_security_group.myterraformnsg.id

    ip_configuration {
        name                          = "login_nic_configuation"
        subnet_id                     = azurerm_subnet.myterraformsubnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.myterraformpublicip.id
    }
}

# Create network interfaces for compute
resource "azurerm_network_interface" "compute_nic" {
    for_each        = local.nodeset
    name                      = each.key
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.myterraformgroup.name
    network_security_group_id = azurerm_network_security_group.myterraformnsg.id

    ip_configuration {
        name                          = "compute_nic_configuration"
        subnet_id                     = azurerm_subnet.myterraformsubnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.myterraformgroup.name
    }
    
    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "mystorageaccount" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = azurerm_resource_group.myterraformgroup.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

resource "azurerm_virtual_machine" "compute" {
    for_each        = local.nodeset
    name                  = each.key
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.myterraformgroup.name
    network_interface_ids = [azurerm_network_interface.compute_nic[each.key].id]
    vm_size               = "Standard_DS1_v2"

    storage_os_disk {
        name              = each.key
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
    }

    storage_image_reference {
        publisher = "OpenLogic"
        offer     = "Centos"
        sku       = "7.6"
        version   = "latest"
    }

    os_profile {
        computer_name  = each.key
        admin_username = "centos"
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path     = "/home/centos/.ssh/authorized_keys"
            key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCs/sxpUsX1hIe3vqHi5ZMtwUsOT7KKrk8n/yX1b/jQGBtO25j9M7PiqxzfynZwKzuSM9TTxMnDMQKtEKXEuuPajK9KFz0err2B9sk1fVLa7s8KXfvXfugbEQFyRzxHy+z8bFR3HJ4cogNeJd2iPGvJwZKx9uYnrfdtWtvfSYXfONofyFi3Bj/XxhXoCatlel/OQGSHF8sOl2KnNls26BAdF5imP5d+c2QYoWlUlTa1u/lLVV/AevxuV0VBzAPGucfH8YB4QLw9D8iKpVBGa7+tHc8K1OWp7SeOGqFBDWHn6/Ct2DHzCKbaqRJCc2TBDIMNS7nuOk+0PPxEzDsRMSqj centos@steveb-control.novalocal"
        }
    }

    boot_diagnostics {
        enabled = "true"
        storage_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
    }
}

resource "azurerm_virtual_machine" "login" {
    name                  = "ohpc-login"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.myterraformgroup.name
    network_interface_ids = [azurerm_network_interface.login_nic.id]
    vm_size               = "Standard_DS1_v2"

    storage_os_disk {
        name              = "ohpc-login-disk"
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
    }

    storage_image_reference {
        publisher = "OpenLogic"
        offer     = "Centos"
        sku       = "7.6"
        version   = "latest"
    }

    os_profile {
        computer_name  = "ohpc-login"
        admin_username = "centos"
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path     = "/home/centos/.ssh/authorized_keys"
            key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCs/sxpUsX1hIe3vqHi5ZMtwUsOT7KKrk8n/yX1b/jQGBtO25j9M7PiqxzfynZwKzuSM9TTxMnDMQKtEKXEuuPajK9KFz0err2B9sk1fVLa7s8KXfvXfugbEQFyRzxHy+z8bFR3HJ4cogNeJd2iPGvJwZKx9uYnrfdtWtvfSYXfONofyFi3Bj/XxhXoCatlel/OQGSHF8sOl2KnNls26BAdF5imP5d+c2QYoWlUlTa1u/lLVV/AevxuV0VBzAPGucfH8YB4QLw9D8iKpVBGa7+tHc8K1OWp7SeOGqFBDWHn6/Ct2DHzCKbaqRJCc2TBDIMNS7nuOk+0PPxEzDsRMSqj centos@steveb-control.novalocal"
        }
    }

    boot_diagnostics {
        enabled = "true"
        storage_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
    }
}

resource "azurerm_public_ip" "myterraformpublicip" {
    name                         = "openhpc-login-ip"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.myterraformgroup.name
    allocation_method            = "Dynamic"
}

data  "template_file" "ohpc" {
    template = "${file("./template/ohpc.tpl")}"
    vars = {
      login = <<EOT
${azurerm_virtual_machine.login.name} ansible_host=${azurerm_network_interface.login_nic.private_ip_address}
EOT
      computes = <<EOT
%{for compute in azurerm_virtual_machine.compute}
${compute.name} ansible_host=${azurerm_network_interface.compute_nic[compute.name].private_ip_address}%{ endfor }
EOT
      fip = "${azurerm_public_ip.myterraformpublicip.ip_address}"
	  control_host = "${var.control_host}"
    }
}

resource "local_file" "hosts" {
  content  = "${data.template_file.ohpc.rendered}"
  filename = "ohpc_hosts"
  depends_on = [azurerm_virtual_machine.compute]
}
