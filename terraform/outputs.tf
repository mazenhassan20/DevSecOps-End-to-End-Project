output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "The name of the created Resource Group"
}

output "kubernetes_cluster_name" {
  value       = azurerm_kubernetes_cluster.aks.name
  description = "The name of the created AKS Cluster"
}

output "key_vault_name" {
  value       = azurerm_key_vault.akv.name
  description = "The name of the created Azure Key Vault"
}

output "database_password" {
  value       = azurerm_key_vault_secret.db_pass_secret.value
  sensitive   = true 
  description = "The generated database password stored in Key Vault"
}