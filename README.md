containerized microservices using AWS Lambda with container images


==> What is this build about!
ECR to host your container images
Lambda functions deployed from container images (up to 10 GB image size, 15‑minute timeout, configurable memory & ephemeral storage)
Optional VPC with private subnets and NAT for internet egress (if your function needs to reach the internet from VPC)
HTTP API (API Gateway v2) to trigger Lambda functions
CloudWatch logs, metrics, alarms; X‑Ray tracing (bonus)
GitHub Actions workflows for Terraform, Docker build & push, and Lambda updates
Assumptions: two microservices (orders and payments), each deployed as its own Lambda function + API route.

==> Repository layout
aws-lambda-containers/
├─ app/
│  ├─ orders/            # microservice 1
│  │  ├─ src/            # application code (handler)
│  │  └─ Dockerfile
│  └─ payments/          # microservice 2
│     ├─ src/
│     └─ Dockerfile
├─ infra/terraform/
│  ├─ main.tf
│  ├─ vpc.tf             # conditional VPC
│  ├─ iam.tf             # roles, policies
│  ├─ ecr.tf
│  ├─ lambda.tf
│  ├─ apigw.tf
│  ├─ cloudwatch.tf
│  ├─ variables.tf
│  └─ outputs.tf
├─ .github/workflows/
│  ├─ terraform.yml      # fmt → init → validate → plan → apply (manual approve)
│  ├─ build-and-push.yml # build & push Docker images to ECR
│  └─ deploy-lambda.yml  # update Lambda functions to latest image digest
