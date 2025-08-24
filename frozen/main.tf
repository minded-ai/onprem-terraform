########################
# S3 bucket (frozen)
########################

resource "aws_s3_bucket" "assets" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = false  # allow our explicit, restrictive bucket policy
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ECS IAM roles (task execution + task role)
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.ecs_cluster_name}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

# Standard AWS-managed execution policy for pulling images, CloudWatch Logs, etc.
resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.ecs_cluster_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

# Bucket policy:
# - Allow GetObject only from specific IP(s)
# - Allow PutObject from the ECS TASK ROLE principal
data "aws_iam_policy_document" "bucket_policy" {
  # READ from specific IP(s)
  statement {
    sid     = "AllowReadFromVpnIps"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = ["${aws_s3_bucket.assets.arn}/*"]

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = var.allowed_read_ip_cidrs
    }
  }

  # WRITE from ECS task role
  statement {
    sid     = "AllowWriteFromEcsTaskRole"
    effect  = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload"
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ecs_task_role.arn]
    }

    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

########################
# ECS (frozen)
########################

resource "aws_ecs_cluster" "this" {
  name = var.ecs_cluster_name
}

# Log group for the task
resource "aws_cloudwatch_log_group" "task" {
  name              = "/ecs/${var.ecs_cluster_name}"
  retention_in_days = 14
}

# Minimal task definition (Fargate)
locals {
  container_name = "app"
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.ecs_cluster_name}-taskdef"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = var.container_image
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.task.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# OPTIONAL ECS service (created only if create_service = true)
resource "aws_ecs_service" "this" {
  count                              = var.create_service ? 1 : 0
  name                               = var.ecs_service_name
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  force_new_deployment               = true
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets         = var.vpc_subnet_ids
    security_groups = [var.service_security_group_id]
    assign_public_ip = false
  }
}
