########################
# S3 bucket
########################

resource "aws_s3_bucket" "assets" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = false
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

resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.ecs_cluster_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

# Bucket policy for read and write controls
data "aws_iam_policy_document" "bucket_policy" {
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
# ECS cluster, task def, optional service
########################

resource "aws_ecs_cluster" "this" {
  name = var.ecs_cluster_name
}

resource "aws_cloudwatch_log_group" "task" {
  name              = "/ecs/${var.ecs_cluster_name}"
  retention_in_days = 14
}

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

########################
# Cross-account role for Minded
########################

data "aws_iam_policy_document" "minded_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.minded_account_id}:root"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "minded_cross_account" {
  name               = "MindedEcsAccessRole"
  assume_role_policy = data.aws_iam_policy_document.minded_trust.json
  description        = "Cross-account role that grants Minded the ability to view/update the ECS resources in this account."
}

data "aws_caller_identity" "current" {}

locals {
  cluster_name    = aws_ecs_cluster.this.name
  logs_group_arn  = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.cluster_name}"
  logs_stream_arn = "${local.logs_group_arn}:log-stream:*"
}

data "aws_iam_policy_document" "minded_perms" {
  statement {
    sid    = "ViewEcsClusterScoped"
    effect = "Allow"
    actions = [
      "ecs:DescribeClusters",
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
      "ecs:ListServices",
      "ecs:ListTasks"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.this.arn]
    }
  }

  statement {
    sid     = "ListClusters"
    effect  = "Allow"
    actions = [
      "ecs:ListClusters"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "LogsReadClusterGroup"
    effect  = "Allow"
    actions = [
      "logs:DescribeLogStreams",
      "logs:GetLogEvents"
    ]
    resources = [
      local.logs_group_arn,
      local.logs_stream_arn
    ]
  }

  statement {
    sid     = "UpdateEcsService"
    effect  = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:UpdateCluster",
      "ecs:UpdateClusterSettings",
      "ecs:PutClusterCapacityProviders"
    ]
    resources = compact([
      aws_ecs_cluster.this.arn,
      length(aws_ecs_service.this) > 0 ? aws_ecs_service.this[0].arn : null
    ])
  }

  statement {
    sid     = "TaskDefinitionReadRegister"
    effect  = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
      "ecs:RegisterTaskDefinition"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "PassEcsRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_task_role.arn,
      aws_iam_role.ecs_task_execution_role.arn
    ]
  }
}

resource "aws_iam_policy" "minded_ecs_policy" {
  name        = "MindedEcsViewUpdate"
  description = "View and update ECS cluster/service; pass the ECS roles."
  policy      = data.aws_iam_policy_document.minded_perms.json
}

resource "aws_iam_role_policy_attachment" "attach_minded" {
  role       = aws_iam_role.minded_cross_account.name
  policy_arn = aws_iam_policy.minded_ecs_policy.arn
}


