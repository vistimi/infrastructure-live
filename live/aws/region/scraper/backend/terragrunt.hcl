include {
  path = find_in_parent_folders()
}

locals {
  convention_vars   = read_terragrunt_config(find_in_parent_folders("convention_override.hcl"))
  account_vars      = read_terragrunt_config(find_in_parent_folders("account_override.hcl"))
  microservice_vars = read_terragrunt_config(find_in_parent_folders("microservice.hcl"))
  project_vars      = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  service_vars      = read_terragrunt_config("${get_terragrunt_dir()}/service_override.hcl")

  organization_name         = local.convention_vars.locals.organization_name
  environment_name          = local.convention_vars.locals.environment_name
  modules_git_host_name     = local.convention_vars.locals.modules_git_host_name
  modules_organization_name = local.convention_vars.locals.modules_organization_name
  modules_repository_name   = local.convention_vars.locals.modules_repository_name
  modules_branch_name       = local.convention_vars.locals.modules_branch_name

  account_region_names = local.account_vars.locals.account_region_names
  account_name         = local.account_vars.locals.account_name
  account_id           = local.account_vars.locals.account_id

  project_name = local.project_vars.locals.project_name

  override_extension_name = local.service_vars.locals.override_extension_name
  common_name             = local.service_vars.locals.common_name
  # organization_name = local.service_vars.locals.organization_name
  repository_name = local.service_vars.locals.repository_name
  branch_name     = local.service_vars.locals.branch_name
  use_fargate     = local.service_vars.locals.use_fargate
  pricing_names   = local.service_vars.locals.pricing_names
  os              = local.service_vars.locals.os
  architecture    = local.service_vars.locals.architecture
  service_count   = local.service_vars.locals.service_count

  config_vars = yamldecode(file("${get_terragrunt_dir()}/config_override.yml"))

  pricing_name_spot      = local.microservice_vars.locals.pricing_name_spot
  pricing_name_on_demand = local.microservice_vars.locals.pricing_name_on_demand
  ec2_user_data = {
    "${local.pricing_name_spot}" = {
      user_data = <<EOT
            #!/bin/bash
            cat <<'EOF' >> /etc/ecs/ecs.config
                ECS_CLUSTER=${local.common_name}
            EOF
        EOT
    }
    "${local.pricing_name_on_demand}" = {
      user_data = <<EOT
            #!/bin/bash
            cat <<'EOF' >> /etc/ecs/ecs.config
                ECS_CLUSTER=${local.common_name}
            EOF
        EOT
    }
  }

  ec2_microservice = local.microservice_vars.locals.ec2
  ec2 = { for pricing_name in local.pricing_names :
    pricing_name => merge(
      local.ec2_microservice[pricing_name],
      {
        user_data            = format("%s\n%s", local.ec2_microservice[pricing_name].user_data, local.ec2_user_data[pricing_name].user_data)
        instance_type        = local.microservice_vars.locals.ec2_instances[local.service_vars.locals.ec2_instance_key].name
        ami_ssm_architecture = local.microservice_vars.locals.ec2_amis["${local.service_vars.locals.os}_${local.service_vars.locals.os_version}"][local.service_vars.locals.architecture].ami_ssm_architecture
        asg = merge(local.ec2_microservice[pricing_name].asg, {
          min_size     = local.service_vars.locals.instance_min_count
          desired_size = local.service_vars.locals.instance_desired_count
          max_size     = local.service_vars.locals.instance_max_count
        })
      }
    )
    if !local.use_fargate
  }


  fargate_microservice = local.microservice_vars.locals.fargate
  fargate = merge(
    local.fargate_microservice,
    {
      os           = local.microservice_vars.locals.fargate_amis[local.service_vars.locals.os][local.service_vars.locals.architecture].os
      architecture = local.microservice_vars.locals.fargate_amis[local.service_vars.locals.os][local.service_vars.locals.architecture].architecture
      capacity_provider = { for pricing_name in local.pricing_names :
        pricing_name => local.fargate_microservice.capacity_provider[pricing_name]
        if local.use_fargate
      }
  })

  task_definition = local.use_fargate ? {
    cpu                = local.microservice_vars.locals.fargate_instances[local.service_vars.locals.fargate_instance_key].cpu
    memory             = local.microservice_vars.locals.fargate_instances[local.service_vars.locals.fargate_instance_key].memory
    memory_reservation = null
    } : {
    cpu                = local.microservice_vars.locals.ec2_instances[local.service_vars.locals.ec2_instance_key].cpu
    memory             = local.microservice_vars.locals.ec2_instances[local.service_vars.locals.ec2_instance_key].memory_allowed - local.microservice_vars.locals.ecs_reserved_memory
    memory_reservation = local.microservice_vars.locals.ec2_instances[local.service_vars.locals.ec2_instance_key].memory_allowed - local.microservice_vars.locals.ecs_reserved_memory
  }

  env_key         = "${local.branch_name}.env"
  env_bucket_name = "${local.common_name}-env"
}

terraform {
  source = "git::git@${local.modules_git_host_name}:${local.modules_organization_name}/${local.modules_repository_name}.git//module/aws/microservice/${local.repository_name}?ref=${local.modules_branch_name}"
}

inputs = {
  common_name = local.common_name
  common_tags = merge(
    local.convention_vars.locals.common_tags,
    local.account_vars.locals.common_tags,
    local.project_vars.locals.common_tags,
    local.service_vars.locals.common_tags,
  )

  microservice = {
    vpc = {
      name       = local.common_name
      cidr_ipv4  = "1.0.0.0/16"
      enable_nat = false
      tier       = "Public"
    }

    bucket_env = {
      name          = local.env_bucket_name
      file_key      = local.env_key
      file_path     = "${local.override_extension_name}.env"
      force_destroy = false
      versioning    = true
    }

    ecs = merge(local.microservice_vars.locals.ecs, {
      traffic = {
        listener_port             = 80
        listener_protocol         = "http"
        listener_protocol_version = "http"
        target_port               = local.config_vars.port
        target_protocol           = "http"
        target_protocol_version   = "http"
        health_check_path         = local.config_vars.healthCheckPath
      }
      service = merge(
        local.microservice_vars.locals.ecs.service,
        {
          use_fargate        = local.use_fargate
          task_desired_count = local.service_count
          deployment_circuit_breaker = local.use_fargate ? null : {
            enable   = true
            rollback = false
          }
        }
      )
      task_definition = merge(
        local.microservice_vars.locals.ecs.task_definition,
        local.task_definition,
        {
          env_bucket_name      = local.env_bucket_name,
          env_file_name        = local.env_key
          repository_name      = lower("${local.organization_name}-${local.repository_name}-${local.branch_name}")
          repository_image_tag = "latest"
        }
      )
      ec2     = local.ec2
      fargate = local.fargate
      },
    )
  }

  dynamodb_tables = [for table in local.config_vars.dynamodb : {
    name                 = table.name
    primary_key_name     = table.primaryKeyName
    primary_key_type     = table.primaryKeyType
    sort_key_name        = table.sortKeyName
    sort_key_type        = table.sortKeyType
    predictable_workload = false
  }]

  bucket_picture = {
    name          = "${local.common_name}-${local.config_vars.buckets.picture.name}"
    force_destroy = false
    versioning    = true
  }
}
