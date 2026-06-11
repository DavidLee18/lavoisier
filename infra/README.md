# Lavoisier on AWS Fargate (M10)

Deploys the `lavoisier` HTTP/WebSocket gateway to **AWS Fargate, arm64, us-west-2** behind an
ALB — RECIPE §9 M10's "validate the shared core on Fargate behind gateways". The image is built
with **Podman** (not Docker); secrets come from **AWS Secrets Manager**; nothing sensitive is
baked into the image or the task definition.

```
client ──HTTP/WS──> ALB :80 ──> Fargate task (lavoisier --serve 0.0.0.0:8080, ARM64)
                                  └ XAI_API_KEY, LVZ_API_KEYS  ← Secrets Manager (env)
                                  └ logs ─> CloudWatch  /ecs/lavoisier
```

The gateway runs **with API-key auth + a rate limit on** (it is internet-facing). Routes:
`GET /health` (ALB checks), `POST /v1/turns` (SSE), `GET /v1/ws`, `GET /metrics` (Prometheus).

## Prerequisites

- AWS account + credentials for **us-west-2** (`aws sts get-caller-identity` works).
- **Podman** and **Terraform ≥ 1.5**. (No local `protoc`/Rust needed — the build runs inside
  the image.)
- An **`XAI_API_KEY`** (the gateway defaults to the xAI gRPC transport).

## 1. Create the secrets

```sh
aws secretsmanager create-secret --region us-west-2 \
  --name lavoisier/xai-api-key      --secret-string "$XAI_API_KEY"
aws secretsmanager create-secret --region us-west-2 \
  --name lavoisier/gateway-api-keys --secret-string "pick-a-strong-key"   # comma-separated for several
```

Copy `terraform/terraform.tfvars.example` → `terraform/terraform.tfvars` and paste the two
secret ARNs the commands print.

## 2. Create the ECR repo, then build + push the image

The repo must exist before the first push, so create it on its own, then push:

```sh
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform apply -target=aws_ecr_repository.app
./infra/scripts/build-and-push.zsh dev          # podman build --platform linux/arm64 + push
```

## 3. Deploy the stack

```sh
./infra/scripts/deploy.zsh                       # terraform apply + force a fresh deployment
```

It prints the ALB URL. Give the service a minute to pull the image and pass health checks.

## 4. Smoke-test (through the ALB)

```sh
ALB="http://$(terraform -chdir=infra/terraform output -raw alb_dns_name)"

curl "$ALB/health"                                            # -> ok
curl -H "Authorization: Bearer pick-a-strong-key" \
     -X POST "$ALB/v1/turns" -d '{"input":"say hi in five words"}'   # -> SSE event stream
curl -X POST "$ALB/v1/turns" -d '{"input":"x"}'               # -> 401 (no key)
curl "$ALB/metrics"                                           # -> Prometheus counters
```

Confirm the task is arm64 and watch logs:

```sh
aws ecs describe-tasks --cluster lavoisier --region us-west-2 \
  --tasks "$(aws ecs list-tasks --cluster lavoisier --region us-west-2 --query 'taskArns[0]' --output text)" \
  --query 'tasks[0].attributes' # or check the task definition's runtimePlatform = ARM64
aws logs tail /ecs/lavoisier --region us-west-2 --follow
```

## 5. Update / roll

Re-push a new image and force a deployment:

```sh
./infra/scripts/build-and-push.zsh dev && ./infra/scripts/deploy.zsh
```

## 6. Teardown

```sh
terraform -chdir=infra/terraform destroy
```

## Notes

- **Cost:** ~1 ALB + 1 Fargate arm64 task (512 CPU / 1024 MiB), **no NAT gateway** (tasks sit
  in public subnets with public IPs for egress). Scale via `desired_count` / `task_cpu`.
- **`/metrics` is unauthenticated** (like `/health`). Fine for this validation; before any real
  exposure, restrict it (an ALB listener rule that 403s `/metrics` from the internet, or move
  scraping to a private path/SG).
- **Production hardening (not built here):** private subnets + NAT gateway, an HTTPS listener
  (ACM cert + a domain), autoscaling, and a WAF.
- The Matrix gateway (`--serve-matrix`) is not deployed here (HTTP-only validation); it needs no
  inbound port and would run as a separate Fargate service long-polling the homeserver.
