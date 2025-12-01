variable "project"        { type = string default = "lambda-microservices" }
variable "environment"    { type = string default = "dev" }
variable "aws_region"     { type = string default = "ap-southeast-2" }

variable "enable_vpc"     { type = bool   default = false }
variable "lambda_memory"  { type = number default = 1024 }        # MB
variable "lambda_timeout" { type = number default = 30 }          # seconds
variable "ephemeral_mb"   { type = number default = 1024 }        # 512–10240
