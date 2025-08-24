# 🚀 How to Use

This repository now provides a way to deploy Minded on-prem assets to AWS.

## Deploy

```bash
terraform init
terraform apply \
  -var 'bucket_name=my-onprem-assets-prod' \
  -var 'allowed_read_ip_cidrs=["203.0.113.10/32"]' \
  -var 'ecs_cluster_name=prod-cluster' \
  -var 'create_service=true' \
  -var 'vpc_subnet_ids=["subnet-abc","subnet-def"]' \
  -var 'service_security_group_id=sg-1234567890abcdef' \
  -var 'minded_account_id=123456789012'
```

## What Gets Created

- S3 bucket with restricted access (VPN IPs for READ, ECS task role for WRITE)
- ECS cluster, log group, task definition, and optional service
- Cross-account IAM role that Minded can assume to view/update the ECS service

## Outputs

- `bucket_arn`
- `ecs_cluster_arn`
- `ecs_service_arn` (null if service not created)
- `ecs_task_role_arn`
- `ecs_task_execution_role_arn`
- `ecs_task_definition_arn`
- `minded_role_arn` (share with Minded so they can assume the role)

## Security Principles

- Least privilege policies for ECS, CloudWatch Logs, and roles pass-through
- S3 bucket denies public access; read limited to provided IP CIDRs; write limited to ECS task role
- All cross-account actions are auditable via CloudTrail under the assumed role