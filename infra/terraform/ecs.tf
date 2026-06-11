resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "main" {
  name = var.name
}

locals {
  image_uri = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = local.image_uri
      essential = true
      command   = ["--serve", "0.0.0.0:8080"]

      portMappings = [
        { containerPort = 8080, protocol = "tcp" }
      ]

      environment = [
        { name = "XAI_TRANSPORT", value = "grpc" },
        { name = "LVZ_RATE_LIMIT", value = tostring(var.rate_limit_per_min) }
      ]

      # Injected from Secrets Manager (never baked into the image or task command).
      secrets = [
        { name = "XAI_API_KEY", valueFrom = var.xai_api_key_secret_arn },
        { name = "LVZ_API_KEYS", valueFrom = var.gateway_api_keys_secret_arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "lavoisier"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = var.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.name
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]
}
