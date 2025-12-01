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
