# ==============================================================================
#  KUBERNETES GESTIONADO (AKS)
# ==============================================================================
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-cp2-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aksunircp2"
  sku_tier            = "Free"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v3" # 2 vCPU
  }

  identity {
    type = "SystemAssigned"
  }
}

# Permiso automático para que AKS pueda descargar imágenes del ACR de forma nativa
resource "azurerm_role_assignment" "aks_to_acr" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

# ==============================================================================
# AUTOMATIZACIÓN DE LA SEGUNDA IMAGEN: BUILD Y PUSH DE APACHE AL ACR
# ==============================================================================

# Empaqueta y sube la aplicación de Apache cada vez que cambia su código o Dockerfile
resource "null_resource" "podman_push_k8s" {
  triggers = {
    # Detecta cambios en la carpeta de la app de Kubernetes (crearemos esta ruta a continuación)
    dockerfile_hash = fileexists("${path.module}/../ansible/mi-app-k8s/Dockerfile") ? filesha256("${path.module}/../ansible/mi-app-k8s/Dockerfile") : "1"
    index_hash      = fileexists("${path.module}/../ansible/mi-app-k8s/index.html") ? filesha256("${path.module}/../ansible/mi-app-k8s/index.html") : "2"
  }

  # Nos aseguramos de que el registro de Azure esté listo antes de subir nada
  depends_on = [azurerm_container_registry.acr]

  provisioner "local-exec" {
    command = <<EOT
      echo "=== [K8S] Iniciando construcción de la imagen de Apache ==="
      podman build -t ${azurerm_container_registry.acr.login_server}/mi-aplicacion2:k8s-apache ${path.module}/../ansible/mi-app-k8s/

      echo "=== [K8S] Autenticando en Azure Container Registry ==="
      podman login ${azurerm_container_registry.acr.login_server} \
              -u ${azurerm_container_registry.acr.admin_username} \
	              -p ${azurerm_container_registry.acr.admin_password}

      echo "=== [K8S] Subiendo imagen de Apache al ACR ==="
      podman push ${azurerm_container_registry.acr.login_server}/mi-aplicacion2:k8s-apache

      echo "=== [K8S] Proceso de imagen finalizado con éxito ==="
    EOT
  }
}

# ==============================================================================
# ORQUESTACIÓN FINAL: EJECUCIÓN AUTOMÁTICA DE ANSIBLE PARA AKS
# ==============================================================================

resource "null_resource" "run_ansible_aks" {
  depends_on = [
    azurerm_kubernetes_cluster.aks,       # Espera a que el clúster esté creado
    azurerm_role_assignment.aks_to_acr,    # Espera a que tenga los permisos de lectura del ACR
    null_resource.podman_push_k8s          #  Espera a que la imagen de Apache esté subida al ACR
  ]

  provisioner "local-exec" {
    command = "ansible-playbook -i ${path.module}/../ansible/inventory.ini ${path.module}/../ansible/playbook-aks.yml"
  }
}
