# terraform/azure/main.tf
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  default = "East US"
}

variable "resource_group_name" {
  default = "credit-app-rg"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Cosmos DB Account (NoSQL - like DynamoDB)
resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }
}

# Cosmos DB Database
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "CreditApplications"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Cosmos DB Container (like DynamoDB table)
resource "azurerm_cosmosdb_sql_container" "main" {
  name                = "Applications"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/userId"

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }
  }

  # Auto-scale throughput (400-4000 RU/s)
  autoscale_settings {
    max_throughput = 4000
  }
}

# Storage Account (required for Azure Functions)
resource "azurerm_storage_account" "main" {
  name                     = "storage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# App Service Plan (Consumption tier for serverless)
resource "azurerm_service_plan" "main" {
  name                = "credit-app-plan"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption (serverless)
}

# Function App
resource "azurerm_linux_function_app" "main" {
  name                = "creditapp-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id

  site_config {
    application_stack {
      node_version = "18"
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~18"
    "COSMOS_DB_CONNECTION"           = azurerm_cosmosdb_account.main.primary_connection_strings[0]
    "COSMOS_DB_ENDPOINT"             = azurerm_cosmosdb_account.main.endpoint
    "COSMOS_DB_KEY"                  = azurerm_cosmosdb_account.main.primary_key
    "DATABASE_NAME"                  = azurerm_cosmosdb_sql_database.main.name
    "CONTAINER_NAME"                 = azurerm_cosmosdb_sql_container.main.name
  }
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "creditapp-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "Node.JS"
}

# Random suffix for unique names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Outputs
output "function_app_name" {
  value = azurerm_linux_function_app.main.name
}

output "function_app_url" {
  value = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "cosmos_db_endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "application_insights_key" {
  value     = azurerm_application_insights.main.instrumentation_key
  sensitive = true
}
