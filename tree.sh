#!/bin/bash
set -euo pipefail

BASE_DIR="aws-lambda"
REGION="ap-southeast-2"  # change if needed

# 1) Create directories
mkdir -p "$BASE_DIR/app/orders/src"
mkdir -p "$BASE_DIR/app/payments/src"
mkdir -p "$BASE_DIR/infra/terraform"
mkdir -p "$BASE_DIR/.github/workflows"

# 2) ----- app/orders/Dockerfile -----
cat > "$BASE_DIR/app/orders/Dockerfile" <<'DOCKER'
# Lambda base image (Node.js 20)
FROM public.ecr.aws/lambda/nodejs:20

# App code
WORKDIR /var/task
COPY src/ ./src/
COPY package*.json ./
RUN npm ci --omit=dev

# Lambda entrypoint: module.function
CMD ["src/handler.handler"]
DOCKER

# 3) ----- app/orders/src/handler.js -----
cat > "$BASE_DIR/app/orders/src/handler.js" <<'JS'
exports.handler = async (event) => {
  return {
    statusCode: 200,
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ service: "orders", method: event?.requestContext?.http?.method || "N/A" }),
  };
};
JS

# 4) ----- app/payments/Dockerfile -----
cat > "$BASE_DIR/app/payments/Dockerfile" <<'DOCKER'
FROM public.ecr.aws/lambda/python:3.11

WORKDIR /var/task
COPY src/ ./src/
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt || true  # optional if no deps

CMD ["src.handler.handler"]
DOCKER

# 5) ----- app/payments/src/handler.py -----
cat > "$BASE_DIR/app/payments/src/handler.py" <<'PY'
import json

def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"service": "payments", "status": "ok"}),
    }
PY

# 6) ----- infra/terraform/variables.tf -----
cat > "$BASE_DIR/infra/terraform/variables.tf" <<'TF'
variable "project"        { type = string default = "lambda-microservices" }
variable "environment"    { type = string default = "dev" }
variable "aws_region"     { type = string default = "ap-southeast-2" }

variable "enable_vpc"     { type = bool   default = false }
variable "lambda_memory"  { type = number default = 1024 }        # MB
variable "lambda_timeout" { type = number default = 30 }          # seconds
variable "ephemeral_mb"   { type = number default = 1024 }        # 512–10240
TF

# 7) ----- infra/terraform/main.tf -----
cat > "$BASE_DIR/infra/terraform/main.tf" <<'TF'
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.project}-${var.environment}"
}
TF

# 8) ----- infra/terraform/vpc.tf -----
cat > "$BASE_DIR/infra/terraform/vpc.tf" <<'TF'
resource "aws_vpc" "this" {
  count                = var.enable_vpc ? 1 : 0
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  count = var.enable_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
}

resource "aws_subnet" "public" {
  count = var.enable_vpc ? 1 : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = "10.10.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "${local.name_prefix}-public" }
}

resource "aws_subnet" "private" {
  count             = var.enable_vpc ? 2 : 0
  vpc_id            = aws_vpc.this[0].id
  cidr_block        = "10.10.${count.index + 1}.0/24"
  availability_zone = "${var.aws_region}${count.index == 0 ? "a" : "b"}"
  tags = { Name = "${local.name_prefix}-private-${count.index}" }
}

resource "aws_eip" "nat" {
  count = var.enable_vpc ? 1 : 0
  domain = "vpc"
}

resource "aws_nat_gateway" "natgw" {
  count         = var.enable_vpc ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
}

resource "aws_route_table" "public" {
  count  = var.enable_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
}

resource "aws_route" "public_to_inet" {
  count                  = var.enable_vpc ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw[0].id
}

resource "aws_route_table_association" "assoc_public" {
  count          = var.enable_vpc ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count  = var.enable_vpc ? 2 : 0
  vpc_id = aws_vpc.this[0].id
}

resource "aws_route" "private_to_nat" {
  count                  = var.enable_vpc ? 2 : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.natgw[0].id
}

resource "aws_route_table_association" "assoc_private" {
  count          = var.enable_vpc ? 2 : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_security_group" "lambda_sg" {
  count  = var.enable_vpc ? 1 : 0
  name   = "${local.name_prefix}-lambda-sg"
  vpc_id = aws_vpc.this[0].id
  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
}
TF

# 9) ----- infra/terraform/iam.tf -----
cat > "$BASE_DIR/infra/terraform/iam.tf" <<'TF'
data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service" identifiers = ["lambda.amazonaws.com"] }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy_attachment" "basic_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  count      = var.enable_vpc ? 1 : 0
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
TF

# 10) ----- infra/terraform/ecr.tf -----
cat > "$BASE_DIR/infra/terraform/ecr.tf" <<'TF'
resource "aws_ecr_repository" "orders" {
  name = "${local.name_prefix}-orders"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "payments" {
  name = "${local.name_prefix}-payments"
  image_scanning_configuration { scan_on_push = true }
}

output "ecr_orders_uri"   { value = aws_ecr_repository.orders.repository_url }
output "ecr_payments_uri" { value = aws_ecr_repository.payments.repository_url }
TF

# 11) ----- infra/terraform/lambda.tf -----
cat > "$BASE_DIR/infra/terraform/lambda.tf" <<'TF'
resource "aws_lambda_function" "orders" {
  function_name  = "${local.name_prefix}-orders"
  package_type   = "Image"
  image_uri      = "${aws_ecr_repository.orders.repository_url}:latest"  # CI will update to digest
  role           = aws_iam_role.lambda_exec.arn
  timeout        = var.lambda_timeout
  memory_size    = var.lambda_memory
  ephemeral_storage { size = var.ephemeral_mb }
  tracing_config { mode = "Active" }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = aws_subnet.private[*].id
      security_group_ids = [aws_security_group.lambda_sg[0].id]
    }
  }
}

resource "aws_lambda_function" "payments" {
  function_name  = "${local.name_prefix}-payments"
  package_type   = "Image"
  image_uri      = "${aws_ecr_repository.payments.repository_url}:latest"
  role           = aws_iam_role.lambda_exec.arn
  timeout        = var.lambda_timeout
  memory_size    = var.lambda_memory
  ephemeral_storage { size = var.ephemeral_mb }
  tracing_config { mode = "Active" }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = aws_subnet.private[*].id
      security_group_ids = [aws_security_group.lambda_sg[0].id]
    }
  }
}
TF

# 12) ----- infra/terraform/apigw.tf -----
cat > "$BASE_DIR/infra/terraform/apigw.tf" <<'TF'
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "orders" {
  api_id                = aws_apigatewayv2_api.http.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.orders.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "payments" {
  api_id                = aws_apigatewayv2_api.http.id
  integration_type      = "AWS_PROXY"
  integration_uri       = aws_lambda_function.payments.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "orders" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /orders"
  target    = "integrations/${aws_apigatewayv2_integration.orders.id}"
}

resource "aws_apigatewayv2_route" "payments" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /payments"
  target    = "integrations/${aws_apigatewayv2_integration.payments.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_orders" {
  statement_id  = "AllowInvokeOrders"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orders.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_payments" {
  statement_id  = "AllowInvokePayments"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.payments.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

output "http_api_endpoint" { value = aws_apigatewayv2_api.http.api_endpoint }
TF

# 13) ----- infra/terraform/cloudwatch.tf -----
cat > "$BASE_DIR/infra/terraform/cloudwatch.tf" <<'TF'
resource "aws_cloudwatch_log_group" "orders" {
  name              = "/aws/lambda/${aws_lambda_function.orders.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "payments" {
  name              = "/aws/lambda/${aws_lambda_function.payments.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_metric_alarm" "orders_errors" {
  alarm_name          = "${local.name_prefix}-orders-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  dimensions = { FunctionName = aws_lambda_function.orders.function_name }
}

resource "aws_cloudwatch_metric_alarm" "payments_duration_p95" {
  alarm_name          = "${local.name_prefix}-payments-duration-p95"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  extended_statistic  = "p95"
  threshold           = 8000
  dimensions = { FunctionName = aws_lambda_function.payments.function_name }
}
TF

# 14) ----- infra/terraform/outputs.tf -----
cat > "$BASE_DIR/infra/terraform/outputs.tf" <<'TF'
output "lambda_orders_name"   { value = aws_lambda_function.orders.function_name }
output "lambda_payments_name" { value = aws_lambda_function.payments.function_name }
TF

# 15) ----- .github/workflows/terraform.yml -----
cat > "$BASE_DIR/.github/workflows/terraform.yml" <<'YAML'
name: Terraform - Plan & Apply
on:
  workflow_dispatch:
  pull_request:
    paths: ["infra/terraform/**"]
jobs:
  terraform:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    env:
      TF_WORKING_DIR: infra/terraform
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_OIDC_ROLE_ARN }}
          aws-region: ap-southeast-2

      - name: Terraform fmt & validate
        working-directory: ${{ env.TF_WORKING_DIR }}
        run: |
          terraform init -input=false
          terraform fmt -check
          terraform validate

      - name: Terraform plan
        working-directory: ${{ env.TF_WORKING_DIR }}
        run: terraform plan -input=false -out=tfplan

      - name: Terraform apply (manual)
        if: github.event_name == 'workflow_dispatch'
        working-directory: ${{ env.TF_WORKING_DIR }}
        run: terraform apply -input=false -auto-approve tfplan
YAML

# 16) ----- .github/workflows/build-and-push.yml -----
cat > "$BASE_DIR/.github/workflows/build-and-push.yml" <<'YAML'
name: Build & Push Docker to ECR
on:
  push:
    paths:
      - "app/**"
      - ".github/workflows/build-and-push.yml"
  workflow_dispatch:

jobs:
  build-push:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    env:
      AWS_REGION: ap-southeast-2
      ORDERS_REPO: ${{ vars.ECR_ORDERS_REPO }}
      PAYMENTS_REPO: ${{ vars.ECR_PAYMENTS_REPO }}
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_OIDC_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build & Push orders
        uses: docker/build-push-action@v5
        with:
          context: ./app/orders
          push: true
          tags: |
            ${{ steps.login-ecr.outputs.registry }}/${{ env.ORDERS_REPO }}:latest
            ${{ steps.login-ecr.outputs.registry }}/${{ env.ORDERS_REPO }}:${{ github.sha }}
          platforms: linux/amd64
        id: build_orders

      - name: Build & Push payments
        uses: docker/build-push-action@v5
        with:
          context: ./app/payments
          push: true
          tags: |
            ${{ steps.login-ecr.outputs.registry }}/${{ env.PAYMENTS_REPO }}:latest
            ${{ steps.login-ecr.outputs.registry }}/${{ env.PAYMENTS_REPO }}:${{ github.sha }}
          platforms: linux/amd64
        id: build_payments

      - name: Export image digests
        run: |
          echo "ORDERS_DIGEST=${{ steps.build_orders.outputs.digest }}" >> $GITHUB_ENV
          echo "PAYMENTS_DIGEST=${{ steps.build_payments.outputs.digest }}" >> $GITHUB_ENV
YAML

# 17) ----- .github/workflows/deploy-lambda.yml -----
cat > "$BASE_DIR/.github/workflows/deploy-lambda.yml" <<'YAML'
name: Deploy Lambda from ECR digest
on:
  workflow_dispatch:
    inputs:
      function:
        description: "orders | payments"
        required: true
        default: "orders"

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    env:
      AWS_REGION: ap-southeast-2
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_OIDC_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Resolve ECR repo & digest
        id: vars
        run: |
          if [ "${{ github.event.inputs.function }}" = "orders" ]; then
            echo "REPO=${{ vars.ECR_ORDERS_REPO }}" >> $GITHUB_ENV
            echo "FUNCTION_NAME=${{ vars.LAMBDA_ORDERS_NAME }}" >> $GITHUB_ENV
          else
            echo "REPO=${{ vars.ECR_PAYMENTS_REPO }}" >> $GITHUB_ENV
            echo "FUNCTION_NAME=${{ vars.LAMBDA_PAYMENTS_NAME }}" >> $GITHUB_ENV
          fi
          ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
          echo "REGISTRY=${ACCOUNT_ID}.dkr.ecr.${{ env.AWS_REGION }}.amazonaws.com" >> $GITHUB_ENV

      - name: Read latest digest from ECR (latest tag)
        id: digest
        run: |
          DIGEST=$(aws ecr describe-images \
            --repository-name "$REPO" \
            --query 'imageDetails[?contains(imageTags, `latest`)].imageDigest' \
            --output text | head -n1)
          echo "DIGEST=$DIGEST" >> $GITHUB_ENV

      - name: Update Lambda code to immutable digest
        run: |
          IMAGE_URI="${REGISTRY}/${REPO}@${DIGEST}"
          aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --image-uri "$IMAGE_URI" \
            --publish

      - name: Output new version
        run: |
          aws lambda get-function --function-name "$FUNCTION_NAME" \
            --query 'Configuration.[Version,LastModified,ImageUri]' --output table
YAML


echo "✅ Project structure and files created under $BASE_DIR"

