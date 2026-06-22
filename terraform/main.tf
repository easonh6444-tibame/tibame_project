terraform {
  backend "s3" {
    bucket = "ckc101-13-bucket-name-12345"
    key    = "terraform/state"
    region = "ap-northeast-1"
  }
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

provider "google" {
  project = "ckc101-13"
  region  = "asia-east1"
}

# api_token 由環境變數 CLOUDFLARE_API_TOKEN 提供（不寫進程式碼/state）
provider "cloudflare" {}

# ── AWS ──────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = "myfirstweb"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# ── AWS ECS ──────────────────────────────────────

resource "aws_ecs_cluster" "app" {
  name = "default"
}

resource "aws_iam_role" "ecs_task_execution" {
  name                  = "ecsTaskExecutionRole"
  force_detach_policies = true
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_cloudwatch" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_ecs_task_definition" "app" {
  count                    = var.enable_compute ? 1 : 0
  family                   = "myfirstweb"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "myfirstweb"
    image     = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
    essential = true
    portMappings = [{ containerPort = 19191, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/myfirstweb"
        "awslogs-region"        = "ap-northeast-1"
        "awslogs-stream-prefix" = "ecs"
        "awslogs-create-group"  = "true"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  count           = var.enable_compute ? 1 : 0
  name            = "myfirstweb-service"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-02ac26d5a7b97921e", "subnet-0fbee793671206e02", "subnet-0c7ee4247d3ddd971"]
    security_groups  = ["sg-02a12b29b431c247f"]
    assign_public_ip = true
  }
}

# ── GCP ──────────────────────────────────────────

resource "google_artifact_registry_repository" "app" {
  repository_id = "myfirstweb"
  location      = "asia-east1"
  format        = "DOCKER"
}

resource "google_cloud_run_v2_service" "app" {
  count               = var.enable_compute ? 1 : 0
  name                = "myfirstweb"
  location            = "asia-east1"
  deletion_protection = false

  template {
    service_account = google_service_account.jenkins_deploy.email
    containers {
      image = "asia-east1-docker.pkg.dev/ckc101-13/myfirstweb/myfirstweb:${var.app_image_tag}"
      ports {
        container_port = 19191
      }
      env {
        name  = "STOCK_BUCKET"
        value = var.stock_bucket
      }
    }
  }
}

# 股票歷史資料持久化用的 GCS bucket（bootstrap：由 owner 建立/管理，
# 不在 Jenkinsfile -target 內；Cloud Run 用 env 字串引用、runtime SA 有 objectAdmin）
resource "google_storage_bucket" "stock_data" {
  name                        = var.stock_bucket
  location                    = "asia-east1"
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket_iam_member" "stock_data_rw" {
  bucket = google_storage_bucket.stock_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.jenkins_deploy.email}"
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.enable_compute ? 1 : 0
  name     = google_cloud_run_v2_service.app[0].name
  location = google_cloud_run_v2_service.app[0].location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ── GCP External HTTPS Load Balancer → Cloud Run (custom domain) ──
# 給 app 一個固定的 anycast IP，讓 ${var.app_domain} 用 A 記錄直接指向 GCP。
# 部署起來 LB 自動把流量導到 Cloud Run service，憑證由 Google 自動簽發。

# Serverless NEG：把 Cloud Run service 接成 LB 的 backend
resource "google_compute_region_network_endpoint_group" "app" {
  count                 = var.enable_compute ? 1 : 0
  name                  = "myfirstweb-neg"
  region                = "asia-east1"
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.app[0].name
  }
}

resource "google_compute_backend_service" "app" {
  count                 = var.enable_compute ? 1 : 0
  name                  = "myfirstweb-backend"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"
  backend {
    group = google_compute_region_network_endpoint_group.app[0].id
  }
}

resource "google_compute_url_map" "app" {
  count           = var.enable_compute ? 1 : 0
  name            = "myfirstweb-urlmap"
  default_service = google_compute_backend_service.app[0].id
}

# Google 託管 SSL 憑證（需 ${var.app_domain} 的 DNS 指到下方 IP 後才會 ACTIVE）
# 名稱帶版本號 + create_before_destroy：要重新觸發驗證時改版本號即可無中斷換證
resource "google_compute_managed_ssl_certificate" "app" {
  count = var.enable_compute ? 1 : 0
  name  = "myfirstweb-cert-1"
  managed {
    domains = [var.app_domain]
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_target_https_proxy" "app" {
  count            = var.enable_compute ? 1 : 0
  name             = "myfirstweb-https-proxy"
  url_map          = google_compute_url_map.app[0].id
  ssl_certificates = [google_compute_managed_ssl_certificate.app[0].id]
}

# 固定的對外 IP（這就是你要在 Cloudflare 用 A 記錄指向的 IP）
resource "google_compute_global_address" "app" {
  count = var.enable_compute ? 1 : 0
  name  = "myfirstweb-ip"
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.enable_compute ? 1 : 0
  name                  = "myfirstweb-fr-https"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.app[0].id
  ip_address            = google_compute_global_address.app[0].id
}

# HTTP(80) → HTTPS 轉址
resource "google_compute_url_map" "https_redirect" {
  count = var.enable_compute ? 1 : 0
  name  = "myfirstweb-http-redirect"
  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "app" {
  count   = var.enable_compute ? 1 : 0
  name    = "myfirstweb-http-proxy"
  url_map = google_compute_url_map.https_redirect[0].id
}

resource "google_compute_global_forwarding_rule" "http" {
  count                 = var.enable_compute ? 1 : 0
  name                  = "myfirstweb-fr-http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.app[0].id
  ip_address            = google_compute_global_address.app[0].id
}

output "app_lb_ip" {
  description = "固定對外 IP；在 Cloudflare 用 A 記錄把 app_domain 指到這裡（DNS-only 灰雲）"
  value       = var.enable_compute ? google_compute_global_address.app[0].address : null
}

# Cloudflare DNS：把 app_domain 的 A 記錄自動指向上面的 LB 固定 IP
# proxied=false（灰雲）讓 Google 託管憑證能完成驗證
resource "cloudflare_record" "app" {
  count   = var.enable_compute ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.app_domain
  type    = "A"
  value   = google_compute_global_address.app[0].address
  proxied = false
  ttl     = 60
}



# ── AWS OIDC (Jenkins) ───────────────────────────

data "tls_certificate" "jenkins" {
  url = "https://jenkins.buy0050.xyz/oidc"
}

resource "aws_iam_openid_connect_provider" "jenkins" {
  url             = "https://jenkins.buy0050.xyz/oidc"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.jenkins.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "jenkins_deploy" {
  name                  = "jenkins-deploy"
  force_detach_policies = true
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.jenkins.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "jenkins.buy0050.xyz/oidc:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr" {
  role       = aws_iam_role.jenkins_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "jenkins_ecs" {
  role       = aws_iam_role.jenkins_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_role_policy" "jenkins_s3_backend" {
  name = "terraform-s3-backend"
  role = aws_iam_role.jenkins_deploy.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::ckc101-13-bucket-name-12345",
        "arn:aws:s3:::ckc101-13-bucket-name-12345/*"
      ]
    }]
  })
}

# ── GCP Workload Identity (Jenkins) ──────────────

resource "google_iam_workload_identity_pool" "jenkins" {
  workload_identity_pool_id = "jenkins-pool"
  display_name              = "Jenkins OIDC Pool"
}

resource "google_iam_workload_identity_pool_provider" "jenkins" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.jenkins.workload_identity_pool_id
  workload_identity_pool_provider_id = "jenkins-provider"
  oidc {
    issuer_uri = "https://jenkins.buy0050.xyz/oidc"
  }
  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }
}

resource "google_service_account" "jenkins_deploy" {
  account_id   = "jenkins-deploy"
  display_name = "Jenkins Deploy SA"
}

resource "google_project_iam_member" "jenkins_artifact_writer" {
  project = "ckc101-13"
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.jenkins_deploy.email}"
}

resource "google_project_iam_member" "jenkins_run_developer" {
  project = "ckc101-13"
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.jenkins_deploy.email}"
}

# 讓 pipeline(jenkins-deploy) 能建立 / 管理 HTTPS Load Balancer 資源
# 用 loadBalancerAdmin（最小必要）而非 compute.admin，避免過度授權
resource "google_project_iam_member" "jenkins_compute_admin" {
  project = "ckc101-13"
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.jenkins_deploy.email}"
}

resource "google_service_account_iam_member" "jenkins_wif_binding" {
  service_account_id = google_service_account.jenkins_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.jenkins.name}/*"
}

# 讓 jenkins-deploy 能 actAs 自己：部署 Cloud Run 指定 runtime SA 時需要
# iam.serviceAccounts.actAs，順帶提供 terraform refresh 需要的 iam.serviceAccounts.get
resource "google_service_account_iam_member" "jenkins_act_as_self" {
  service_account_id = google_service_account.jenkins_deploy.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.jenkins_deploy.email}"
}

output "aws_jenkins_role_arn" {
  value = aws_iam_role.jenkins_deploy.arn
}

output "gcp_workload_identity_provider" {
  value = "projects/${google_service_account.jenkins_deploy.project}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.jenkins.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.jenkins.workload_identity_pool_provider_id}"
}

output "gcp_service_account" {
  value = google_service_account.jenkins_deploy.email
}
