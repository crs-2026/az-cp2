
# 1. GRUPO DE RECURSOS (Swedencentral)
resource "azurerm_resource_group" "rg" {
  name     = "rg-cp2-demo-s1"
  location = "swedencentral"
}

# 2. AZURE CONTAINER REGISTRY (ACR)
resource "azurerm_container_registry" "acr" {
  name                = "acrunircp2jristo" # Debe ser único en todo Azure
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# 3. RED VIRTUAL Y SUBNET
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-cp2"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-vm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Archivo de variables automáticas de Ansible para el ACR
resource "local_file" "ansible_vars" {
  filename = "${path.module}/../ansible/acr_vars.yml"

  content = templatefile("${path.module}/acr_vars.tmpl", {
    acr_server = azurerm_container_registry.acr.login_server
    acr_user   = azurerm_container_registry.acr.admin_username
    acr_pass   = azurerm_container_registry.acr.admin_password
    image_tag  = "casopractico2"
    image_name = "mi-aplicacion1"
  })
}
