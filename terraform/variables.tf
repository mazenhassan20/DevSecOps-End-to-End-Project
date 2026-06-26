variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in Azure"
  default     = "blogapp-rg"
}

variable "location" {
  type        = string
  description = "Azure region for deploying resources"
  default     = "East US"
}

variable "cluster_name" {
  type        = string
  description = "Name of the AKS cluster"
  default     = "blogapp-aks"
}

variable "vnet_name" {
  type        = string
  description = "Name of the Virtual Network"
  default     = "blogapp-vnet"
}