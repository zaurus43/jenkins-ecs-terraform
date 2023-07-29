# Availability Zone
data "aws_availability_zones" "this" { }

# My IP address
data "http" "ipify" {
    url = "http://api.ipify.org"
}
locals {
    myip         = chomp(data.http.ipify.body)
    allowed_cidr = "${local.myip}/32"
}

# Get availability zone name on setted region
locals {
    cidr_main = "10.0.0.0/16"
    azs = slice(data.aws_availability_zones.this.names, 0, var.num_azs)
}

# main VPC
module "vpc" {
    source               = "terraform-aws-modules/vpc/aws"

    name                 = "${var.project}-${var.environment}-vpc"
    cidr                 = local.cidr_main
    azs                  = local.azs
    enable_dns_hostnames = true
    enable_dns_support   = true

    public_subnets       = [for k, v in local.azs : cidrsubnet(local.cidr_main, 4, k)]
    public_subnet_names  = [for k, v in local.azs : "${var.project}-${var.environment}-subnet-public${k+1}-${v}"]
}

# Security group rule for main VPC
resource "aws_security_group_rule" "egress_all" {
    type              = "egress"
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
    security_group_id = module.vpc.default_security_group_id
}
resource "aws_security_group_rule" "ingress_from_alb" {
    type                     = "ingress"
    from_port                = 8080
    to_port                  = 8080
    protocol                 = "tcp"
    source_security_group_id = module.alb.security_group_id
    security_group_id        = module.vpc.default_security_group_id
}

# Load Balancer for ECS
module "alb" {
    source             = "terraform-aws-modules/alb/aws"
  
    name               = "${var.project}-${var.environment}-alb"
    load_balancer_type = "application"

    vpc_id             = module.vpc.vpc_id
    subnets            = module.vpc.public_subnets

    security_group_rules = {
        ingress_from_myip = {
            type        = "ingress"
            from_port   = 8080
            to_port     = 8080
            protocol    = "tcp"
            cidr_blocks = [local.allowed_cidr]
        }
        egress_all = {
            type        = "egress"
            from_port   = 0
            to_port     = 0
            protocol    = "-1"
            cidr_blocks = ["0.0.0.0/0"]
        }
    }
    target_groups = [
        {
            name             = "${var.project}-${var.environment}-targetgroup"
            target_type      = "ip"
            backend_protocol = "HTTP"
            backend_port     = 80
            health_check     = {
                enabled             = true
                interval            = 30
                path                = "/login"
                port                = "traffic-port"
                protocol            = "HTTP"
                timeout             = 5
                healthy_threshold   = 5
                unhealthy_threshold = 2
                matcher             = "200"
            }
        }
    ]
    http_tcp_listeners = [
        {
            port               = 8080
            protocol           = "HTTP"
            target_group_index = 0
            type               = "forward"
        }
    ]
}
