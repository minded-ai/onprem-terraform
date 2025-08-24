output "bucket_arn" {
  value = aws_s3_bucket.assets.arn
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "ecs_service_arn" {
  value       = try(aws_ecs_service.this[0].id, null)
  description = "ECS service ARN (null if create_service=false)"
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task_role.arn
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "minded_role_arn" {
  value       = aws_iam_role.minded_cross_account.arn
  description = "Provide this ARN to Minded so they can assume the role."
}


