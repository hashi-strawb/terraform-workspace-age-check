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

  # Because we're using "plantimestamp", and check{}
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

  # The last state update
  workspaces_and_modify_dates = {
    for k, ws in local.workspaces_without_ignored :
    # Remove millisecond precision from timestamp
    k => replace(ws.latest-change-at, "/....Z/", "Z")
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

output "workspace_modify_dates" {
  value = local.workspaces_and_modify_dates
}

/*
output "now" {
  value = plantimestamp()
}
*/

resource "time_offset" "too_old" {
  for_each     = local.workspaces_and_modify_dates
  base_rfc3339 = each.value

  offset_hours = var.offset_hours
}

locals {
  old_workspaces = {
    for workspace_name, offset in time_offset.too_old :
    workspace_name => local.workspaces[workspace_name]
    if timecmp(offset.rfc3339, plantimestamp()) < 0
    && local.workspaces[workspace_name].resource-count > 0
  }

  old_workspace_names = keys(local.old_workspaces)
}

/*
output "old_workspace_names" {
  value = local.old_workspace_names
}

output "old_workspaces" {
  value = local.old_workspaces
}
*/

check "workspace_ages" {
  assert {
    condition     = length(local.old_workspace_names) == 0
    error_message = "The following workspaces, with managed resources, are old: ${join(", ", local.old_workspace_names)}"
  }
}
