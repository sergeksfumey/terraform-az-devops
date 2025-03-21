# 🔹 Create Resource Group
resource "azurerm_resource_group" "example" {
  name     = "SFTSRG"
  location = "FranceCentral"
}

# 🔹 Virtual Network
resource "azurerm_virtual_network" "example_vnet" {
  name                = "TSVNet"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.0.0.0/16"]
}

# 🔹 Subnet for Application Gateway
resource "azurerm_subnet" "appgw_subnet" {
  name                 = "AppGwSubnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example_vnet.name
  address_prefixes     = ["10.0.3.0/24"]  # Ensure this does not overlap with other subnets
}

# 🔹 Subnets
resource "azurerm_subnet" "vm_subnet" {
  name                 = "VMSubnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "AKSSubnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# 🔹 Network Security Group
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "VMNSG"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

# 🔹 Allow SSH Access
resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "AllowSSH"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  network_security_group_name = azurerm_network_security_group.vm_nsg.name
  resource_group_name         = azurerm_resource_group.example.name
}

# 🔹 Attach NSG to VM Subnet
resource "azurerm_subnet_network_security_group_association" "vm_nsg_assoc" {
  subnet_id                 = azurerm_subnet.vm_subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# 🔹 Virtual Machine Scale Set (Corrected Version)
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "TSVMSS"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = "Standard_B2s"
  instances           = 2
  admin_username      = "azureuser"

  network_interface {
    name    = "VMSSNetwork"
    primary = true
    ip_configuration {
      name      = "IPConfig"
      subnet_id = azurerm_subnet.vm_subnet.id
      primary   = true
    }
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

# 🔹 Auto-Scaling for VMSS (Fixed)
resource "azurerm_monitor_autoscale_setting" "vm_autoscale" {
  name                = "VM-AutoScale"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id

  profile {
    name = "default"

    capacity {
      default = 2
      minimum = 2
      maximum = 4
    }

    # ✅ Required `fixed_date` schedule instead of `recurrence`
    fixed_date {
      start = "2024-03-19T00:00:00Z"
      end   = "2025-03-19T23:59:00Z"
    }

    rule {
      metric_trigger {
    metric_name        = "Percentage CPU"
    metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
    operator           = "GreaterThan"
    threshold          = 75
    time_aggregation   = "Average"
    statistic          = "Average"
    time_grain         = "PT1M"
    time_window        = "PT5M"  # Example: 5-minute window
  }

      scale_action {
        direction     = "Increase"
        type          = "ChangeCount"
        value         = 1
        cooldown      = "PT5M"
      }
    }

    rule {
      metric_trigger {
    metric_name        = "Percentage CPU"
    metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
    operator           = "LessThan"
    threshold          = 25
    time_aggregation   = "Average"
    statistic          = "Average"
    time_grain         = "PT1M"
    time_window        = "PT5M"  # Example: 5-minute window
  }

      scale_action {
        direction     = "Decrease"
        type          = "ChangeCount"
        value         = 1
        cooldown      = "PT5M"
      }
    }
  }
}


# 🔹 Azure Kubernetes Service (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "tsAKS"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  dns_prefix          = "tsaks"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

# 🔹 SQL Database
resource "azurerm_mssql_server" "sqlserver" {
  name                         = "tssqlserver01"
  resource_group_name          = azurerm_resource_group.example.name
  location                     = azurerm_resource_group.example.location
  version                      = "12.0"
  administrator_login          = "adminuser"
  administrator_login_password = "SecurePassword123!"
}

resource "azurerm_mssql_database" "sqldb" {
  name           = "tsDB"
  server_id      = azurerm_mssql_server.sqlserver.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb    = 2
  sku_name       = "Basic"
}

# 🔹 Create Public IP for Application Gateway
resource "azurerm_public_ip" "appgw_pip" {
  name                = "AppGwPublicIP"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  allocation_method   = "Static"
  sku                 = "Standard"  # ✅ Ensure this is "Standard" SKU
}

# 🔹 Application Gateway (Corrected)
resource "azurerm_application_gateway" "appgw" {
  name                = "TSAppGateway"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
  name      = "GatewayIPConfig"
  subnet_id = azurerm_subnet.appgw_subnet.id  # ✅ Fixed Reference
}

  frontend_ip_configuration {
    name                 = "FrontendIPConfig"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id  # ✅ Fixed Reference
  }

  frontend_port {
    name = "FrontendPort"
    port = 80
  }

  backend_address_pool {
    name = "BackendPool"
  }

  http_listener {
    name                           = "HTTPListener"
    frontend_ip_configuration_name = "FrontendIPConfig"
    frontend_port_name             = "FrontendPort"
    protocol                       = "Http"
  }

  backend_http_settings {
    name                  = "BackendHTTPSettings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
  }

  request_routing_rule {
    name                       = "RoutingRule"
    rule_type                  = "Basic"
    http_listener_name         = "HTTPListener"
    backend_address_pool_name  = "BackendPool"
    backend_http_settings_name = "BackendHTTPSettings"
    priority                   = 100  # ✅ Add Priority (Required for API v2021-08-01 and later)
  }
}

