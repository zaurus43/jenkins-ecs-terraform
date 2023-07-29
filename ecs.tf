# Container name
locals {
    container_name = "jenkins-master"
}

# Cluster
resource "aws_ecs_cluster" "this" {
    name = "${var.project}-${var.environment}-cluster"
}

# Task definition
resource "aws_ecs_task_definition" "this" {
    family                   = "${var.project}-${var.environment}-task-definition"
    cpu                      = 1024
    memory                   = 3072
    requires_compatibilities = ["FARGATE"]
    execution_role_arn       = aws_iam_role.ecs_task_execution.arn
    network_mode             = "awsvpc"
    container_definitions    = <<-EOS
    [
        {
        "name"        : "${local.container_name}",
        "image"       : "${aws_ecr_repository.this.repository_url}:${var.image_tag}",
        "cpu"         : 0,
        "portMappings": [
            {
                "name": "${local.container_name}-8080-tcp",
                "containerPort": 8080,
                "hostPort": 8080,
                "protocol": "tcp",
                "appProtocol": "http"
            },
            {
                "name": "${local.container_name}-50000-tcp",
                "containerPort": 50000,
                "hostPort": 50000,
                "protocol": "tcp",
                "appProtocol": "http"
            }
        ],
        "essential": true,
        "ulimits": [],
        "environment": [],
        "environmentFiles": [],
        "mountPoints": [
            {
                "sourceVolume": "jenkins-home",
                "containerPath": "/var/jenkins_home",
                "readOnly": false
            }
        ],
        "volumesFrom": [],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-create-group": "true",
                "awslogs-group": "/ecs/${var.project}-${var.environment}-task-definition",
                "awslogs-region": "${var.region}",
                "awslogs-stream-prefix": "ecs"
            }
        }
    }
  ]
  EOS
  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
  volume {
    name = "jenkins-home"
    efs_volume_configuration {
      file_system_id          = module.efs.id
      root_directory          = "/jenkins_home"
    }
  }
}
resource "aws_cloudwatch_log_group" "this" {
    name = "/ecs/${var.project}-${var.environment}-task-definition"
}

# Service
resource "aws_ecs_service" "this" {
    name                               = "${var.project}-${var.environment}-${local.container_name}"
    cluster                            = aws_ecs_cluster.this.id
    task_definition                    = aws_ecs_task_definition.this.arn
    launch_type                        = "FARGATE"
    desired_count                      = 1
    health_check_grace_period_seconds  = 300
    deployment_minimum_healthy_percent = 0
    deployment_maximum_percent         = 100
    network_configuration {
        subnets = module.vpc.public_subnets
        security_groups  = [module.vpc.default_security_group_id]
        assign_public_ip = true
    }
    load_balancer {
        target_group_arn = module.alb.target_group_arns[0]
        container_name   = local.container_name
        container_port   = 8080
    }
}