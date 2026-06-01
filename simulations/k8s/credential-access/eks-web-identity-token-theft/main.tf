terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster to target"
  type        = string
}

provider "aws" {
  skip_region_validation      = true
  skip_credentials_validation = true
}

provider "azurerm" {
  features {}
}

# Configured via KUBECONFIG env var set by the k8s connector
provider "kubernetes" {}

variable "resource_prefix" {
  type = string
}

locals {
  # Random selection of non-US Azure regions for attacker VM deployment
  azure_regions = [
    "West Europe",
    "North Europe",
    "UK South",
    "Germany West Central",
    "France Central",
    "Australia East",
    "Japan East",
    "Southeast Asia",
    "Canada Central",
    "Brazil South"
  ]
  selected_azure_region = local.azure_regions[random_integer.region_selector.result]
}

resource "random_integer" "region_selector" {
  min = 0
  max = length(local.azure_regions) - 1
}

resource "random_string" "random" {
  length    = 6
  min_lower = 6
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ================================
# EKS Cluster Data (for OIDC issuer)
# ================================

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

# ================================
# OIDC Provider for IRSA
# ================================

locals {
  oidc_issuer     = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  oidc_issuer_url = replace(local.oidc_issuer, "https://", "")
  namespace       = "simrun-${random_string.random.result}"
  sa_name         = "stolen-identity-sa"
  pod_name        = "token-holder-${random_string.random.result}"
}

# Look up the existing OIDC provider for the cluster
data "aws_iam_openid_connect_provider" "cluster" {
  url = local.oidc_issuer
}

# ================================
# IAM Role (target of AssumeRoleWithWebIdentity)
# ================================

resource "aws_iam_role" "web_identity_role" {
  name = "${var.resource_prefix}-web-identity-${random_string.random.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.cluster.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_url}:sub" = "system:serviceaccount:${local.namespace}:${local.sa_name}"
            "${local.oidc_issuer_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Attach a read-only policy so the assumed role can make harmless API calls
resource "aws_iam_role_policy" "web_identity_policy" {
  name = "${var.resource_prefix}-web-identity-policy-${random_string.random.result}"
  role = aws_iam_role.web_identity_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# ================================
# Kubernetes Resources
# ================================

resource "kubernetes_namespace" "this" {
  metadata {
    name = local.namespace
  }
}

resource "kubernetes_service_account" "this" {
  metadata {
    name      = local.sa_name
    namespace = kubernetes_namespace.this.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.web_identity_role.arn
    }
  }
}

# ================================
# Token Holder Pod
# ================================

# Long-running pod that mounts a projected OIDC token (same as IRSA pods receive).
# The Go simulation code execs into this pod to steal the token, generating
# realistic K8s audit log events for exec operations.
resource "kubernetes_pod_v1" "token_holder" {
  metadata {
    name      = local.pod_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    service_account_name = kubernetes_service_account.this.metadata[0].name

    container {
      name    = "token-holder"
      image   = "050879227952.dkr.ecr.us-west-2.amazonaws.com/confluentinc/aws-cli-v2:2.27.33-r0-202506102223"
      command = ["sh", "-c", "while true; do sleep 3600; done"]

      volume_mount {
        name       = "aws-iam-token"
        mount_path = "/var/run/secrets/eks.amazonaws.com/serviceaccount"
        read_only  = true
      }
    }

    volume {
      name = "aws-iam-token"
      projected {
        sources {
          service_account_token {
            path               = "token"
            expiration_seconds = 86400
            audience           = "sts.amazonaws.com"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service_account.this]
}

# ================================
# Azure Infrastructure (Attacker VM)
# ================================

resource "azurerm_resource_group" "attacker_rg" {
  name     = "${var.resource_prefix}-attacker-rg-${random_string.random.result}"
  location = local.selected_azure_region
}

resource "azurerm_virtual_network" "attacker_vnet" {
  name                = "${var.resource_prefix}-attacker-vnet-${random_string.random.result}"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.attacker_rg.location
  resource_group_name = azurerm_resource_group.attacker_rg.name
}

resource "azurerm_subnet" "attacker_subnet" {
  name                 = "${var.resource_prefix}-attacker-subnet-${random_string.random.result}"
  resource_group_name  = azurerm_resource_group.attacker_rg.name
  virtual_network_name = azurerm_virtual_network.attacker_vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_public_ip" "attacker_ip" {
  name                = "${var.resource_prefix}-attacker-pip-${random_string.random.result}"
  location            = azurerm_resource_group.attacker_rg.location
  resource_group_name = azurerm_resource_group.attacker_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "attacker_nsg" {
  name                = "${var.resource_prefix}-attacker-nsg-${random_string.random.result}"
  location            = azurerm_resource_group.attacker_rg.location
  resource_group_name = azurerm_resource_group.attacker_rg.name

  security_rule {
    name                       = "AllowAWSAPIs"
    priority                   = 1001
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "attacker_nic" {
  name                = "${var.resource_prefix}-attacker-nic-${random_string.random.result}"
  location            = azurerm_resource_group.attacker_rg.location
  resource_group_name = azurerm_resource_group.attacker_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.attacker_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.attacker_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "attacker_nsg_association" {
  network_interface_id      = azurerm_network_interface.attacker_nic.id
  network_security_group_id = azurerm_network_security_group.attacker_nsg.id
}

resource "tls_private_key" "attacker_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_ssh_public_key" "attacker_ssh" {
  name                = "${var.resource_prefix}-attacker-ssh-${random_string.random.result}"
  resource_group_name = azurerm_resource_group.attacker_rg.name
  location            = azurerm_resource_group.attacker_rg.location
  public_key          = tls_private_key.attacker_ssh.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.attacker_ssh.private_key_pem
  filename        = "/tmp/simrun_ssh_key"
  file_permission = "0600"
}

resource "azurerm_linux_virtual_machine" "attacker_vm" {
  name                = "${var.resource_prefix}-attacker-vm-${random_string.random.result}"
  location            = azurerm_resource_group.attacker_rg.location
  resource_group_name = azurerm_resource_group.attacker_rg.name
  size                = "Standard_B1s"
  admin_username      = "azureuser"

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.attacker_nic.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.attacker_ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y awscli jq curl
  EOF
  )
}

# ================================
# Outputs
# ================================

output "role_arn" {
  description = "ARN of the IAM role that can be assumed with web identity"
  value       = aws_iam_role.web_identity_role.arn
}

output "oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster"
  value       = local.oidc_issuer
}

output "namespace" {
  description = "Kubernetes namespace containing the pod"
  value       = local.namespace
}

output "service_account_name" {
  description = "Kubernetes service account name"
  value       = local.sa_name
}

output "pod_name" {
  description = "Name of the token holder pod"
  value       = local.pod_name
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.cluster_name
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

output "attacker_vm_public_ip" {
  description = "Public IP address of the attacker Azure VM"
  value       = azurerm_public_ip.attacker_ip.ip_address
}

output "attacker_vm_user" {
  description = "Username for SSH access to Azure VM"
  value       = "azureuser"
}

output "attacker_vm_private_key_path" {
  description = "Path to the SSH private key for the Azure VM"
  value       = local_file.ssh_private_key.filename
}

output "azure_region" {
  description = "Azure region where the attacker VM is deployed"
  value       = local.selected_azure_region
}

output "display" {
  value = format(
    "EKS web identity token theft simulation ready: role %s in namespace %s on cluster %s, attacker VM %s in Azure %s",
    aws_iam_role.web_identity_role.arn,
    local.namespace,
    var.cluster_name,
    azurerm_public_ip.attacker_ip.ip_address,
    local.selected_azure_region,
  )
}
