terraform {
  cloud {
    organization = "fancycorp"
    #organization = "lmhd"

    workspaces {
      name = "workspace-ages"
      #name = "age-check"
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

  # Because we're using "plantimestamp"
  required_version = ">= 1.5.0"
}



variable "org" {
  default = "fancycorp"
}

variable "offset_hours" {
  type    = number
  default = 24
}

provider "tfe" {
  organization = var.org
}

variable "workspace_ignore_tag" {
  type    = string
  default = "age-check:ignore"
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
  url  = "https://app.terraform.io/api/v2/organizations/${var.org}/workspaces/${each.key}"

  method = "GET"

  headers = {
    Authorization = "Bearer ${data.environment_variables.tfe_token.items["TFE_TOKEN"]}"
    Content-Type  = "application/vnd.api+json"
  }
  response_codes = [200]

}

locals {
  workspaces = {
    for k, ws in data.terracurl_request.workspace :
    k => jsondecode(ws.response).data.attributes
  }

  workspaces_without_ignored = {
    for k, ws in local.workspaces :
    k => ws
    # We are ignoring workspaces with this tag
    if !contains(ws.tag-names, var.workspace_ignore_tag)
  }

  workspaces_and_creation_dates = {
    for k, ws in local.workspaces_without_ignored :
    # Remove millisecond precision from timestamp
    k => replace(ws.created-at, "/....Z/", "Z")
  }
}

/*
output "workspaces" {
  value = local.workspaces_without_ignored
}
*/

output "workspace_creation_dates" {
  value = local.workspaces_and_creation_dates
}

/*
output "now" {
  value = plantimestamp()
}
*/

resource "time_offset" "too_old" {
  for_each     = local.workspaces_and_creation_dates
  base_rfc3339 = each.value

  offset_hours = var.offset_hours

  lifecycle {
    postcondition {
      condition     = timecmp(self.rfc3339, plantimestamp()) > 0
      error_message = "The workspace ${each.key} is old"
    }
  }
}
