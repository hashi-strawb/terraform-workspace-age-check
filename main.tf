terraform {
  cloud {
    organization = "fancycorp"

    workspaces {
      name = "workspace-ages"
    }
  }

  required_providers {
    tfe = {
      source = "hashicorp/tfe"
    }
    environment = {
      source  = "EppO/environment"
      version = "1.3.4"
    }
    terracurl = {
      source = "devops-rob/terracurl"
    }
  }

  # Because we're using "terraform_data"
  required_version = ">= 1.4.0"
}



provider "tfe" {
  organization = "fancycorp"
}



#
# List all Workspaces
#


data "tfe_workspace_ids" "all" {
  names = ["*"]
}

data "environment_variables" "tfe_token" {
  filter = "TFE_TOKEN"
}

# Need TerraCurl to get created-at, because the TFE provider does not supply this info
data "terracurl_request" "workspace" {
  for_each = data.tfe_workspace_ids.all.ids

  name = each.key
  url  = "https://app.terraform.io/api/v2/organizations/fancycorp/workspaces/${each.key}"

  method = "GET"

  headers = {
    Authorization = "Bearer ${data.environment_variables.tfe_token.items["TFE_TOKEN"]}"
    Content-Type  = "application/vnd.api+json"
  }
  response_codes = [200]

}

locals {
  workspaces_and_creation_dates = {
    for k, v in data.terracurl_request.workspace :
    # Remove millisecond precision from timestamp
    k => replace(jsondecode(v.response).data.attributes.created-at, "/....Z/", "Z")
  }
}

output "workspace_creation_dates" {
  value = local.workspaces_and_creation_dates
}

output "now" {
  value = timestamp()
}

resource "time_offset" "too_old" {
  for_each     = local.workspaces_and_creation_dates
  base_rfc3339 = each.value

  offset_hours = 12

  lifecycle {
    postcondition {
      condition     = timecmp(self.rfc3339, timestamp()) > 0
      error_message = "The workspace ${each.key} is old"
    }
  }
}
