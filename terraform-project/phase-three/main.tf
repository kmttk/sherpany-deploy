# Resource group
resource "azurerm_resource_group" "rg" {
    name     = "sherpany-vm-rg"
    location = "westeurope"
}

# Virtual network and subnet
resource "azurerm_virtual_network" "vnet" {
    name                = "ubuntu-vnet"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
    name                 = "ubuntu-subnet"
    resource_group_name  = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
    name                = "ubuntu-nsg"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range         = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

# Public IP
resource "azurerm_public_ip" "pip" {
    name                = "ubuntu-pip"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    allocation_method   = "Dynamic"
}

# Network Interface
resource "azurerm_network_interface" "nic" {
    name                = "ubuntu-nic"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id         = azurerm_public_ip.pip.id
    }
}

# Storage Account for logs
resource "azurerm_storage_account" "logs" {
    name                     = "ubuntulogstorage"
    resource_group_name      = azurerm_resource_group.rg.name
    location                 = azurerm_resource_group.rg.location
    account_tier             = "Standard"
    account_replication_type = "LRS"
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
    name                = "ubuntu-vm"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    size                = "Standard_B2s"
    admin_username      = "adminuser"
    admin_password      = var.azure_linux_vm_secret
    disable_password_authentication = false

    network_interface_ids = [
        azurerm_network_interface.nic.id,
    ]

    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "20_04-lts-gen2"
        version   = "latest"
    }

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.logs.primary_blob_endpoint
    }
}
