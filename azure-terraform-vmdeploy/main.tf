##############################################################################
# 
# This Terraform configuration will create the following:
#
# Resource group with a virtual network and subnet
# An Ubuntu Linux server running Apache

##############################################################################
# * Shared infrastructure resources
# You can find a complete list of Azure resources supported by Terraform here:
# https://www.terraform.io/docs/providers/azurerm/
resource "azurerm_resource_group" "tf_azure_guide" {
  name     = "${var.resource_group}"
  location = "${var.location}"
}

# The next resource is a Virtual Network. We can dynamically place it into the
# resource group without knowing its name ahead of time. Terraform handles all
# of that for you, so everything is named consistently every time.
# GraphViz tool: http://www.webgraphviz.com/
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.virtual_network_name}"
  location            = "${azurerm_resource_group.tf_azure_guide.location}"
  address_space       = ["${var.address_space}"]
  resource_group_name = "${azurerm_resource_group.tf_azure_guide.name}"
}

# The next resource is a subnet to run our VMs in. These variables can be defined 
# via environment variables, a config file, or command line flags. Default 
# values will be used if the user does not override them. 
resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}subnet"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  resource_group_name  = "${azurerm_resource_group.tf_azure_guide.name}"
  address_prefix       = "${var.subnet_prefix}"
}

##############################################################################
# * Build an Ubuntu 16.04 Linux VM
#
# Now that we have a network, we'll deploy an Ubuntu 16.04 Linux server.
# An Azure Virtual Machine has several components. In this example we'll build
# a security group, a network interface, a public ip address, a storage 
# account and finally the VM itself. Terraform handles all the dependencies 
# automatically, and each resource is named with user-defined variables.

# Security group to allow inbound access on port 80 (http) and 22 (ssh)
resource "azurerm_network_security_group" "tf-guide-sg" {
  name                = "${var.prefix}-sg"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.tf_azure_guide.name}"

  security_rule {
    name                       = "HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "${var.source_network}"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${var.source_network}"
    destination_address_prefix = "*"
  }
}

# A network interface. This is required by the azurerm_virtual_machine 
# resource. Terraform will let you know if you're missing a dependency.
resource "azurerm_network_interface" "tf-guide-nic" {
  name                      = "${var.prefix}tf-guide-nic"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.tf_azure_guide.name}"
  network_security_group_id = "${azurerm_network_security_group.tf-guide-sg.id}"

  ip_configuration {
    name                          = "${var.prefix}ipconfig"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.tf-guide-pip.id}"
  }
}

# Every Azure Virtual Machine comes with a private IP address. You can also 
# optionally add a public IP address for Internet-facing applications and 
# demo environments like this one.
resource "azurerm_public_ip" "tf-guide-pip" {
  name                         = "${var.prefix}-ip"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.tf_azure_guide.name}"
  public_ip_address_allocation = "Dynamic"
  domain_name_label            = "${var.hostname}"
}

# And finally we build our virtual machine. This is a standard Ubuntu instance.
# We use the shell provisioner to run a Bash script that configures Apache for 
# the demo environment. Terraform supports several different types of 
# provisioners including Bash, Powershell and Chef.
resource "azurerm_virtual_machine" "site" {
  name                = "${var.hostname}-site"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.tf_azure_guide.name}"
  vm_size             = "${var.vm_size}"

  network_interface_ids         = ["${azurerm_network_interface.tf-guide-nic.id}"]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = "${var.image_publisher}"
    offer     = "${var.image_offer}"
    sku       = "${var.image_sku}"
    version   = "${var.image_version}"
  }

  storage_os_disk {
    name              = "${var.hostname}-osdisk"
    managed_disk_type = "Standard_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "${var.hostname}"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  # It's easy to transfer files or templates using Terraform.
  provisioner "file" {
    source      = "files/setup.sh"
    destination = "/home/${var.admin_username}/setup.sh"

    connection {
      type     = "ssh"
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.tf-guide-pip.fqdn}"
    }
  }

  # This shell script starts our Apache server and prepares the demo environment.
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/${var.admin_username}/setup.sh",
      "sudo /home/${var.admin_username}/setup.sh",
    ]

    connection {
      type     = "ssh"
      user     = "${var.admin_username}"
      password = "${var.admin_password}"
      host     = "${azurerm_public_ip.tf-guide-pip.fqdn}"
    }
  }
}

