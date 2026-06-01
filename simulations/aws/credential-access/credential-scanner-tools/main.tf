terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  skip_region_validation      = true
  skip_credentials_validation = true
}

provider "azurerm" {
  features {}
}

variable "resource_prefix" {
  type = string
}

locals {
  # Random selection of Azure regions
  azure_regions = [
    "West Europe",
    "North Europe",
    "UK South",
    "France Central",
    "Australia East",
    "Japan East",
    "Southeast Asia",
    "Canada Central"
  ]

  selected_azure_region = local.azure_regions[random_integer.region_selector.result]
}

resource "random_string" "random" {
  length    = 6
  min_lower = 6
}

resource "random_integer" "region_selector" {
  min = 0
  max = length(local.azure_regions) - 1
}

# ===== AWS Resources =====

# Create IAM user for credential scanning target
resource "aws_iam_user" "target_user" {
  name = "${var.resource_prefix}-cred-scanner-user-${random_string.random.result}"

  tags = {
    Description = "Target user for credential scanner testing"
  }
}

# Create minimal policy for the IAM user (read-only EC2)
resource "aws_iam_policy" "target_policy" {
  name        = "${var.resource_prefix}-cred-scanner-policy-${random_string.random.result}"
  description = "Minimal policy for credential scanner target user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeRegions"]
        Resource = "*"
      }
    ]
  })
}

# Attach policy to user
resource "aws_iam_user_policy_attachment" "target_user_policy" {
  user       = aws_iam_user.target_user.name
  policy_arn = aws_iam_policy.target_policy.arn
}

# Create access key for the IAM user
resource "aws_iam_access_key" "target_user_key" {
  user = aws_iam_user.target_user.name
}

# ===== Azure Resources =====

# Create Azure Resource Group
resource "azurerm_resource_group" "this" {
  name     = "${var.resource_prefix}-cred-scanner-aws-rg-${random_string.random.result}"
  location = local.selected_azure_region
}

# Create Virtual Network
resource "azurerm_virtual_network" "this" {
  name                = "${var.resource_prefix}-cred-scanner-aws-vnet-${random_string.random.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

# Create Subnet
resource "azurerm_subnet" "this" {
  name                 = "${var.resource_prefix}-cred-scanner-aws-subnet-${random_string.random.result}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create Public IP
resource "azurerm_public_ip" "this" {
  name                = "${var.resource_prefix}-cred-scanner-aws-pip-${random_string.random.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create Network Security Group
resource "azurerm_network_security_group" "this" {
  name                = "${var.resource_prefix}-cred-scanner-aws-nsg-${random_string.random.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

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

# Create Network Interface
resource "azurerm_network_interface" "this" {
  name                = "${var.resource_prefix}-cred-scanner-aws-nic-${random_string.random.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# Generate SSH key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key to local file
resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "/tmp/${var.resource_prefix}-cred-scanner-aws-key-${random_string.random.result}.pem"
  file_permission = "0600"
}

# Create Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "this" {
  name                = "${var.resource_prefix}-cred-scanner-aws-vm-${random_string.random.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = "Standard_B2s"
  admin_username      = "azureuser"

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.this.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  # Use Ubuntu 22.04 LTS
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Custom data to install required tools
  custom_data = base64encode(<<-EOF
#!/bin/bash
set -e

# Update and install dependencies
apt-get update
apt-get install -y curl wget git unzip jq apt-transport-https ca-certificates gnupg awscli

# Install trufflehog
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin

# Install kingfisher manually (x64 architecture for Standard_B2s VM)
curl -fLsS "https://github.com/mongodb/kingfisher/releases/latest/download/kingfisher-linux-x64.tgz" -o /tmp/kingfisher.tgz
tar -C /tmp -xzf /tmp/kingfisher.tgz
install -m 0755 /tmp/kingfisher /usr/local/bin/kingfisher
rm -f /tmp/kingfisher.tgz /tmp/kingfisher

# Verify installations
echo "Verifying tool installations..."
which trufflehog && trufflehog --version || echo "trufflehog not found"
which kingfisher && kingfisher --version || echo "kingfisher not found"

echo "Setup complete" > /tmp/setup_complete.txt
EOF
  )
}

# ===== Outputs =====

output "vm_name" {
  description = "Name of the Azure VM"
  value       = azurerm_linux_virtual_machine.this.name
}

output "resource_group_name" {
  description = "Name of the Azure resource group"
  value       = azurerm_resource_group.this.name
}

output "attacker_vm_public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.this.ip_address
}

output "azure_region" {
  description = "Azure region where the VM is deployed"
  value       = local.selected_azure_region
}

output "attacker_vm_private_key_path" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "attacker_vm_user" {
  description = "Username for SSH access to Azure VM"
  value       = "azureuser"
}

output "aws_access_key_id" {
  description = "AWS Access Key ID for the target user"
  value       = aws_iam_access_key.target_user_key.id
  sensitive   = true
}

output "aws_secret_access_key" {
  description = "AWS Secret Access Key for the target user"
  value       = aws_iam_access_key.target_user_key.secret
  sensitive   = true
}

output "aws_user_name" {
  description = "Name of the AWS IAM user"
  value       = aws_iam_user.target_user.name
}

output "display" {
  value = format("Azure VM %s in %s ready for AWS credential scanning. AWS user: %s",
    azurerm_linux_virtual_machine.this.name,
    local.selected_azure_region,
    aws_iam_user.target_user.name
  )
}
