variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Minded Onprem S3 bucket name"
  type        = string
  default     = "minded-onprem-assets-prod"
}

variable "allowed_read_ip_cidrs" {
  description = "CIDR(s) allowed to READ (GetObject) directly from the bucket"
  type        = list(string)
  default     = ["203.0.113.10/32"] # replace with your VPN egress IP(s)
}

variable "ecs_cluster_name" {
  description = "Minded Onprem ECS cluster name"
  type        = string
  default     = "minded-onprem-ecs-cluster"
}

variable "ecs_service_name" {
  description = "Minded Onprem ECS service name"
  type        = string
  default     = "minded-onprem-ecs-svc"
}

variable "container_image" {
  description = "Container image for the sample task"
  type        = string
  default     = "public.ecr.aws/amazonlinux/amazonlinux:latest"
}

variable "container_port" {
  description = "Container port to expose"
  type        = number
  default     = 8080
}

variable "fargate_cpu" {
  type        = string
  default     = "256"
}

variable "fargate_memory" {
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Desired count for the ECS service"
  type        = number
  default     = 1
}

variable "vpc_subnet_ids" {
  description = "Private subnet IDs for the ECS service (awsvpc). Required to create the service."
  type        = list(string)
  default     = []
}

variable "service_security_group_id" {
  description = "Security group ID for the ECS service ENIs"
  type        = string
  default     = ""
}

variable "create_service" {
  description = "Set true to create the ECS service (requires vpc_subnet_ids and service_security_group_id)"
  type        = bool
  default     = false
}
