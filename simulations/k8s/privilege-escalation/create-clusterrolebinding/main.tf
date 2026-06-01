terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configured via KUBECONFIG env var set by the k8s connector
provider "kubernetes" {}


variable "resource_prefix" {
  type = string
}

resource "random_string" "random" {
  length    = 6
  min_lower = 6
}

resource "kubernetes_cluster_role_binding" "this" {
  metadata {
    name = "${var.resource_prefix}-admin-binding-${random_string.random.result}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "User"
    name      = "attacker@example.com"
    api_group = "rbac.authorization.k8s.io"
  }
}

output "binding_name" {
  description = "Name of the created ClusterRoleBinding"
  value       = kubernetes_cluster_role_binding.this.metadata[0].name
}

output "cluster_role" {
  description = "ClusterRole bound by the binding"
  value       = kubernetes_cluster_role_binding.this.role_ref[0].name
}

output "subject_name" {
  description = "Subject granted the ClusterRole"
  value       = kubernetes_cluster_role_binding.this.subject[0].name
}

output "display" {
  value = format(
    "ClusterRoleBinding %s grants %s to %s",
    kubernetes_cluster_role_binding.this.metadata[0].name,
    kubernetes_cluster_role_binding.this.role_ref[0].name,
    kubernetes_cluster_role_binding.this.subject[0].name,
  )
}
