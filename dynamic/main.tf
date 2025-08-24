########################
# Cross-account role for Minded (dynamic)
########################

# Trust policy: allow Minded account to assume this role
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

# Caller identity and convenience locals for scoping
data "aws_caller_identity" "current" {}

locals {
  cluster_name     = element(split("/", var.ecs_cluster_arn), 1)
  logs_group_arn   = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.cluster_name}"
  logs_stream_arn  = "${local.logs_group_arn}:log-stream:*"
}

# Permissions for viewing/listing and updating ECS resources.
# - Describe*, List* for visibility
# - UpdateService for deployments
# - (optional) UpdateClusterSettings, PutClusterCapacityProviders for cluster-level tweaks
# - iam:PassRole on the ECS task and execution roles so they can point the service at new task definitions that use those roles
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
      values   = [var.ecs_cluster_arn]
    }
  }

  # Some list operations do not support resource-level scoping
  statement {
    sid     = "ListClusters"
    effect  = "Allow"
    actions = [
      "ecs:ListClusters"
    ]
    resources = ["*"]
  }

  # Restrict CloudWatch Logs read access to the cluster log group
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
      var.ecs_cluster_arn,
      var.ecs_service_arn != "" ? var.ecs_service_arn : null
    ])
  }

  # Allow updating a service to a new task definition:
  # they need to read/resolve task definitions; scope Register to "*" or remove if not desired.
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

  # Allow passing ONLY the ECS roles you created in frozen/
  statement {
    sid     = "PassEcsRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      var.ecs_task_role_arn,
      var.ecs_task_execution_role_arn
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

output "minded_role_arn" {
  value       = aws_iam_role.minded_cross_account.arn
  description = "Provide this ARN to Minded so they can assume the role."
}
