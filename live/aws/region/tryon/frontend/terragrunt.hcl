include {
  path = find_in_parent_folders()
}

locals {
  convention_tmp_vars = read_terragrunt_config(find_in_parent_folders("convention_override.hcl"))
  convention_vars     = read_terragrunt_config(find_in_parent_folders("convention.hcl"))
  account_vars        = read_terragrunt_config(find_in_parent_folders("account_override.hcl"))
  microservice_vars   = read_terragrunt_config(find_in_parent_folders("microservice.hcl"))
  service_tmp_vars    = read_terragrunt_config("${get_terragrunt_dir()}/service_override.hcl")

  override_extension_name       = local.convention_tmp_vars.locals.override_extension_name
  modules_git_host_auth_method  = local.convention_tmp_vars.locals.modules_git_host_auth_method
  modules_git_host_name         = local.convention_tmp_vars.locals.modules_git_host_name
  modules_organization_name     = local.convention_tmp_vars.locals.modules_organization_name
  modules_repository_name       = local.convention_tmp_vars.locals.modules_repository_name
  modules_repository_visibility = local.convention_tmp_vars.locals.modules_repository_visibility
  modules_branch_name           = local.convention_tmp_vars.locals.modules_branch_name

  modules_git_prefix = local.convention_vars.locals.modules_git_prefix

  domain_name         = local.account_vars.locals.domain_name
  account_region_name = local.account_vars.locals.account_region_name
  account_name        = local.account_vars.locals.account_name
  account_id          = local.account_vars.locals.account_id

  branch_name = local.service_tmp_vars.locals.branch_name

  config = yamldecode(
    templatefile(
      "${get_terragrunt_dir()}/config.yml",
      {
        vpc_id            = get_env("VPC_ID")
        branch_name       = local.branch_name
        port              = 3000
        health_check_path = "/ping"
        zone              = local.domain_name
        subdomain_prefix  = local.branch_name == "trunk" ? "" : "${local.branch_name}."
        bucket_file_path  = "${get_terragrunt_dir()}/viton-hd.txt"
      }
    )
  )

  path                = regex("^.*/(?P<project_name>[0-9A-Za-z!_-]+)/(?P<service_name>[0-9A-Za-z!_-]+)$", get_terragrunt_dir())
  organization_name_s = substr(local.convention_tmp_vars.locals.organization_name, 0, 2)
  project_name_s      = join("", [for str in split("-", local.path.project_name) : substr(str, 0, 2)])
  service_name_s      = join("", [for str in split("-", local.path.service_name) : substr(str, 0, 2)])
  prefix_name_s       = join("", [local.organization_name_s, local.project_name_s, local.service_name_s])
  branch_name_s       = join("", [for str in split("-", local.branch_name) : substr(str, 0, 5)])
  account_name_s      = join("", [for str in split("-", local.account_name) : substr(str, 0, 5)])
  region_name_s       = join("", [for str in split("-", local.account_region_name) : substr(str, 0, 1)])
  name                = lower(join("-", [local.prefix_name_s, local.branch_name_s, local.account_name_s, local.region_name_s]))

  tags = merge(
    local.convention_tmp_vars.locals.tags,
    local.account_vars.locals.tags,
    local.config.inputs.tags,
  )
}

terraform {
  source = "tfr:///vistimi/microservice/aws//?version=0.0.10"
}

inputs = merge(
  local.config.inputs,
  {
    name = local.name
    tags = local.tags
  }
)
