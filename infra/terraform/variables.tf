variable "region" {
  description = "AWS region (RECIPE §10 pins us-west-2)."
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "lavoisier"
}

variable "image_tag" {
  description = "Image tag to deploy from the stack's ECR repo (build + push it with infra/scripts/build-and-push.zsh)."
  type        = string
  default     = "dev"
}

variable "task_cpu" {
  description = "Fargate task CPU units (256/512/1024/...)."
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate task memory, MiB."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Number of gateway tasks to run."
  type        = number
  default     = 1
}

variable "rate_limit_per_min" {
  description = "Per-principal gateway request quota per 60s window (LVZ_RATE_LIMIT)."
  type        = number
  default     = 60
}

variable "xai_api_key_secret_arn" {
  description = "Secrets Manager ARN of the xAI API key (plaintext secret -> env XAI_API_KEY)."
  type        = string
}

variable "gateway_api_keys_secret_arn" {
  description = "Secrets Manager ARN of the comma-separated gateway API keys (plaintext -> env LVZ_API_KEYS)."
  type        = string
}

variable "az_count" {
  description = "Number of AZs / public subnets."
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR for the gateway VPC."
  type        = string
  default     = "10.20.0.0/16"
}
