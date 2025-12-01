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
