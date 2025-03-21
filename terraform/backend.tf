terraform {
  backend "azurerm" {
    resource_group_name   = "TerraformStateRG"
    storage_account_name  = "skftfstatestorage01"
    container_name        = "terraform-state"
    key                   = "terraform.tfstate"
  }
}

