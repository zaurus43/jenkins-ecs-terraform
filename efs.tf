# property of file system
locals {
    name = "${var.project}-${var.environment}-efs"
}

module "efs" {
    source                           = "terraform-aws-modules/efs/aws"

    name                             = local.name
    availability_zone_name           = var.num_azs == 1 ? module.vpc.azs[0] : null
    creation_token                   = local.name
    encrypted                        = false
    performance_mode                 = "generalPurpose"
    throughput_mode                  = "bursting"
    provisioned_throughput_in_mibps  = null
    attach_policy                    = false
    mount_targets                    = { for k, v in zipmap(module.vpc.azs, module.vpc.public_subnets) : k => { subnet_id = v } }
    security_group_description       = "Example EFS security group"
    security_group_vpc_id            = module.vpc.vpc_id
    security_group_rules = {
        ingress_vpc = {
            description              = "NFS ingress from main VPC"
            type                     = "ingress"
            source_security_group_id = module.vpc.default_security_group_id
        }
    }
    enable_backup_policy             = false
    create_replication_configuration = false
    tags = {
        "Name"                       = local.name
    }
}

