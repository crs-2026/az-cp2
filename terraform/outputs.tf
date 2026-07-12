output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "Servidor de login para el ACR"
}

output "acr_admin_username" {
  value       = azurerm_container_registry.acr.admin_username
  description = "Usuario administrador del ACR"
}

output "acr_admin_password" {
  value     = azurerm_container_registry.acr.admin_password
  sensitive = true
}

output "vm_public_ip" {
  value       = azurerm_public_ip.public_ip.ip_address
  description = "IP Pública de la VM Linux"
}
