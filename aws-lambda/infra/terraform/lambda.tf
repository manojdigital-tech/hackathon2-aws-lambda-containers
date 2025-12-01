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
