# 🚀 How to Use

This infrastructure is split into two layers:

- frozen/: Baseline, rarely changing resources
  - S3 bucket with restricted access (VPN IPs for READ, ECS task role for WRITE)
  - ECS cluster, task definition, and optional service
- dynamic/: Flexible, frequently changing access policies
  - Cross-account IAM role that grants Minded the ability to view and update ECS services securely

## 1) Deploy the Frozen Layer

```bash
cd frozen
terraform init
terraform apply \
  -var 'bucket_name=my-frozen-assets-prod' \
  -var 'allowed_read_ip_cidrs=["203.0.113.10/32"]' \
  -var 'ecs_cluster_name=prod-cluster' \
  -var 'create_service=true' \
  -var 'vpc_subnet_ids=["subnet-abc","subnet-def"]' \
  -var 'service_security_group_id=sg-1234567890abcdef'
```

Outputs:

- S3 bucket ARN
- ECS cluster ARN
- ECS service ARN (if created)
- ECS task role ARN
- ECS execution role ARN
- ECS task definition ARN

Keep these handy—you will feed them into the `dynamic/` layer.

## 2) Deploy the Dynamic Layer

```bash
cd ../dynamic
terraform init
terraform apply \
  -var 'minded_account_id=123456789012' \
  -var 'ecs_cluster_arn=arn:aws:ecs:us-east-1:111122223333:cluster/prod-cluster' \
  -var 'ecs_service_arn=arn:aws:ecs:us-east-1:111122223333:service/prod-cluster/frozen-ecs-svc' \
  -var 'ecs_task_role_arn=arn:aws:iam::111122223333:role/prod-cluster-task' \
  -var 'ecs_task_execution_role_arn=arn:aws:iam::111122223333:role/prod-cluster-exec'
```

Output:

- ARN of the cross-account role that Minded can assume

Share this ARN with the Minded team so they can configure their side.

## 3) Security Principles

- Frozen resources are tightly locked down—no direct public access
- Dynamic access follows least privilege: Minded can only view/update the specified ECS cluster/service, not the entire account
- All cross-account actions are logged in CloudTrail under the assumed role