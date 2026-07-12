# ==============================================================================
# INFRAESTRUCTURA DE RED ESPECÍFICA PARA LA VM
# ==============================================================================

# IP Pública Standard/Static
resource "azurerm_public_ip" "public_ip" {
  name                = "pip-vm-linux"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  allocation_method   = "Static"
}

# Interfaz de Red (NIC)
resource "azurerm_network_interface" "nic" {
  name                = "nic-vm-linux"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

# Cortafuegos (NSG) para permitir el tráfico SSH (Ansible) y HTTPS (Web Segura)
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-vm-linux"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Vinculación del Cortafuegos (NSG) a la Interfaz de Red
resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ==============================================================================
# SEGURIDAD CRIPTOGRÁFICA (Generación universal de claves SSH)
# ==============================================================================

# Genera una clave RSA privada de 4096 bits en la memoria de Terraform
resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Guarda la clave privada en un archivo físico dentro de la carpeta de Ansible
resource "local_file" "private_key" {
  content         = tls_private_key.vm_ssh_key.private_key_pem
  filename        = "${path.module}/../ansible/id_rsa_vm"
  file_permission = "0600" # Permiso requerido estrictamente por SSH de Linux
}

# ==============================================================================
# MÁQUINA VIRTUAL LINUX
# ==============================================================================

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "cp2unir-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B2ats_v2" # Económica y compatible
  admin_username                  = "adminuser"
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  # Inyecta la clave pública correspondiente en la VM de Azure
  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.vm_ssh_key.public_key_openssh
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
}

# ==============================================================================
# GENERACIÓN DE ENTORNOS PARA ANSIBLE (Inventario dinámico)
# ==============================================================================

# Construye el archivo inventory.ini a partir de la plantilla y los datos de Azure
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"

  content = templatefile("${path.module}/inventory.tmpl", {
    vm_ip        = azurerm_public_ip.public_ip.ip_address
    vm_user      = "adminuser"
    ssh_key_path = "${path.module}/../ansible/id_rsa_vm"
  })

  depends_on = [local_file.private_key]
}

# ==============================================================================
# AUTOMATIZACIÓN DE CONTENEDORES: BUILD Y PUSH LOCAL
# ==============================================================================

# Empaqueta y sube la aplicación web al registro de Azure cada vez que cambia el código fuente
resource "null_resource" "podman_push" {
  triggers = {
    dockerfile_hash = fileexists("${path.module}/../ansible/mi-app-web/Dockerfile") ? filesha256("${path.module}/../ansible/mi-app-web/Dockerfile") : "1"
    index_hash      = fileexists("${path.module}/../ansible/mi-app-web/index.html") ? filesha256("${path.module}/../ansible/mi-app-web/index.html") : "2"
  }

  depends_on = [azurerm_container_registry.acr]

  provisioner "local-exec" {
    command = <<EOT
      echo "=== Iniciando construcción de la imagen ==="
      podman build -t ${azurerm_container_registry.acr.login_server}/mi-aplicacion1:casopractico2 ${path.module}/../ansible/mi-app-web/

      echo "=== Autenticando en Azure Container Registry ==="
      podman login ${azurerm_container_registry.acr.login_server} \
        -u ${azurerm_container_registry.acr.admin_username} \
        -p ${azurerm_container_registry.acr.admin_password}

      echo "=== Subiendo imagen al ACR ==="
      podman push ${azurerm_container_registry.acr.login_server}/mi-aplicacion1:casopractico2

      echo "=== Proceso finalizado con éxito ==="
    EOT
  }
}

# ==============================================================================
# ORQUESTACIÓN FINAL: EJECUCIÓN AUTOMÁTICA DE ANSIBLE
# ==============================================================================

# Dispara la configuración interna de la VM de forma desatendida cuando todo lo anterior está listo
resource "null_resource" "run_ansible" {
  depends_on = [
    azurerm_linux_virtual_machine.vm,
    local_file.ansible_inventory,
    local_file.private_key,
    null_resource.podman_push # Obligatorio que la imagen ya esté subida al ACR antes de configurar Nginx
  ]

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ../ansible/inventory.ini ../ansible/playbook-vm.yml"
  }
}
