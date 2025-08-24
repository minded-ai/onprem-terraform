variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "minded_account_id" {
  description = "External Minded AWS account ID (12 digits)"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ECS cluster ARN created in frozen/"
  type        = string
}

variable "ecs_service_arn" {
  description = "ECS service ARN (optional if you didn't create a service)"
  type        = string
  default     = ""
}

variable "ecs_task_role_arn" {
  description = "Task role ARN from frozen/"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "Task execution role ARN from frozen/"
  type        = string
}
