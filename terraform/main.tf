# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# 2 VNet
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 3.(Azure Key Vault) 
data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_key_vault" "akv" {
  name                        = "blogapp-kv-${random_string.suffix.result}"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false 

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"]
  }
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "db_pass_secret" {
  name         = "postgres-password"
  value        = random_password.db_password.result
  key_vault_id = azurerm_key_vault.akv.id
}

# 5.Kubernetes Cluster (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "blogapp"

  # Security:(RBAC)
  role_based_access_control_enabled = true

 
  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name           = "default"
    node_count     = 1 
    vm_size        = "Standard_B2s_v2" 
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.240.0.0/16" 
    dns_service_ip    = "10.240.0.10"   
  }
  
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }
}