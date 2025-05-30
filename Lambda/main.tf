provider "aws" {
  region = "eu-central-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.240.0.0/24"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.240.0.0/25"
  availability_zone = "eu-central-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.240.0.128/25"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# SG for ALB
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["92.53.12.166/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM role
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda
resource "aws_lambda_function" "sum_lambda" {
  filename         = "${path.module}/application/large-number-addition-lambda-1.0-SNAPSHOT.jar"
  function_name    = "test-function"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "scalability.cloud.App::handleRequest"
  runtime          = "java21"
  source_code_hash = filebase64sha256("${path.module}/application/large-number-addition-lambda-1.0-SNAPSHOT.jar")
  timeout          = 30
  memory_size      = 1769
}

# ALB
resource "aws_lb" "alb" {
  name               = "lambda-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups    = [aws_security_group.alb_sg.id]
  idle_timeout       = 3600
}

resource "aws_lb_target_group" "lambda_tg" {
  name        = "lambda-tg"
  target_type = "lambda"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "lambda_attach" {
  target_group_arn = aws_lb_target_group.lambda_tg.arn
  target_id        = aws_lambda_function.sum_lambda.arn

  depends_on = [
    aws_lambda_permission.alb_invoke
  ]
}

resource "aws_lambda_permission" "alb_invoke" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sum_lambda.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg.arn
}

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}
