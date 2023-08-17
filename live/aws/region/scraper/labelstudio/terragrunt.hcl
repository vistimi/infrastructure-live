locals {
  convention_tmp_vars = read_terragrunt_config(find_in_parent_folders("convention_override.hcl"))
  convention_vars     = read_terragrunt_config(find_in_parent_folders("convention_override.hcl"))
  account_vars        = read_terragrunt_config(find_in_parent_folders("account_override.hcl"))
  service_vars        = read_terragrunt_config("${get_terragrunt_dir()}/service.hcl")
  service_tmp_vars    = read_terragrunt_config("${get_terragrunt_dir()}/service_override.hcl")

  account_region_name = local.account_vars.locals.account_region_name
  account_name        = local.account_vars.locals.account_name
  account_id          = local.account_vars.locals.account_id

  project_name      = local.service_vars.locals.project_name
  service_name      = local.service_vars.locals.service_name
  git_host_name     = local.service_vars.locals.git_host_name
  organization_name = local.service_vars.locals.organization_name
  repository_name   = local.service_vars.locals.repository_name

  branch_name = local.service_tmp_vars.locals.branch_name

  name_prefix = substr(local.convention_tmp_vars.locals.organization_name, 0, 2)

  tags = merge(
    local.convention_vars.locals.tags,
    local.account_vars.locals.tags,
    local.service_vars.locals.tags,
  )
}

# Generate version block
generate "versions" {
  path      = "version_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
    terraform {
      required_version = "~> 1.4.4"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "= 4.63.0"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "= 2.9.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "= 2.19.0"
        }
        kubectl = {
          source  = "gavinbunney/kubectl"
          version = "= 1.14.0"
        }
        tls = {
          source  = "hashicorp/tls"
          version = "= 4.0.4"
        }
        random = {
          source  = "hashicorp/random"
          version = "= 3.4.3"
        }
      }
    }
EOF
}

generate "provider" {
  path      = "provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
    provider "aws" {
      region = "${local.aws_account_region}"
      # allowed_account_ids = ["${local.aws_account_id}"]
    }
    provider "kubernetes" {
      host                   = data.aws_eks_cluster.eks.endpoint
      cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
      token                  = data.aws_eks_cluster_auth.eks.token
    }

    provider "kubectl" {
      host                   = data.aws_eks_cluster.eks.endpoint
      cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
      token                  = data.aws_eks_cluster_auth.eks.token
    }

    provider "helm" {
      kubernetes {
        host                   = data.aws_eks_cluster.eks.endpoint
        cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
        token                  = data.aws_eks_cluster_auth.eks.token
      }

      ## Doesn't work with alb-ingress-controller manifest
      #  experiments {
      #    manifest = true
      #  }
    }

    provider "random" {
    }
EOF
}

# Configure Terragrunt to automatically store tfstate files in an S3 bucket
remote_state {
  backend = "s3"
  config = {
    encrypt             = true
    key                 = "${path_relative_to_include()}/terraform.tfstate"
    region              = local.account_region_name
    bucket              = lower(join("-", compact([local.name_prefix, local.repository_name, local.account_name, local.branch_name, "tf-state"])))
    dynamodb_table      = lower(join("-", compact([local.name_prefix, local.repository_name, local.account_name, local.branch_name, "tf-locks"])))
    s3_bucket_tags      = local.tags
    dynamodb_table_tags = local.tags
  }

  generate = {
    path      = "backend_override.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Extra arguments when running commands
terraform {
  # Force Terraform to keep trying to acquire a lock for some minutes if someone else already has the lock
  extra_arguments "retry_lock" {
    commands  = get_terraform_commands_that_need_locking()
    arguments = ["-lock-timeout=10m"]
  }
}

locals {
  convention_tmp_vars = read_terragrunt_config(find_in_parent_folders("convention_override.hcl"))
  convention_vars     = read_terragrunt_config(find_in_parent_folders("convention.hcl"))
  account_vars        = read_terragrunt_config(find_in_parent_folders("account_override.hcl"))
  microservice_vars   = read_terragrunt_config(find_in_parent_folders("microservice.hcl"))
  service_vars        = read_terragrunt_config("${get_terragrunt_dir()}/service.hcl")

  override_extension_name       = local.convention_tmp_vars.locals.override_extension_name
  modules_git_host_auth_method  = local.convention_tmp_vars.locals.modules_git_host_auth_method
  modules_git_host_name         = local.convention_tmp_vars.locals.modules_git_host_name
  modules_organization_name     = local.convention_tmp_vars.locals.modules_organization_name
  modules_repository_name       = local.convention_tmp_vars.locals.modules_repository_name
  modules_repository_visibility = local.convention_tmp_vars.locals.modules_repository_visibility
  modules_branch_name           = local.convention_tmp_vars.locals.modules_branch_name

  modules_git_prefix = local.convention_vars.locals.modules_git_prefix

  domain_name         = local.account_vars.locals.domain_name
  domain_suffix       = local.account_vars.locals.domain_suffix
  account_region_name = local.account_vars.locals.account_region_name
  account_name        = local.account_vars.locals.account_name
  account_id          = local.account_vars.locals.account_id

  config_vars = yamldecode(file("${get_terragrunt_dir()}/config_override.yml"))
}

terraform {
  source = "${local.modules_git_prefix}//projects/module/aws/microservice/${local.repository_name}?ref=${local.modules_branch_name}"
}

inputs = {
  name_prefix = substr(local.convention_tmp_vars.locals.organization_name, 0, 2)
  name_suffix = local.name

  # vpc = local.service_vars.locals.vpc

  iam = local.service_vars.locals.iam

  bucket_label = local.service_vars.locals.bucket_label

  tags = merge(
    local.convention_tmp_vars.locals.tags,
    local.account_vars.locals.tags,
    local.service_vars.locals.tags,
  )
}
