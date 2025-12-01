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
