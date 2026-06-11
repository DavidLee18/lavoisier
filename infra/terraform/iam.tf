data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: pull the image, ship logs, and read the two secrets into the container env.
resource "aws_iam_role" "execution" {
  name_prefix        = "${var.name}-exec-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets_read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.xai_api_key_secret_arn, var.gateway_api_keys_secret_arn]
  }
}

resource "aws_iam_role_policy" "secrets_read" {
  name_prefix = "${var.name}-secrets-"
  role        = aws_iam_role.execution.id
  policy      = data.aws_iam_policy_document.secrets_read.json
}

# Task role: the app makes no AWS API calls (secrets arrive as env), so it carries no policy.
resource "aws_iam_role" "task" {
  name_prefix        = "${var.name}-task-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}
