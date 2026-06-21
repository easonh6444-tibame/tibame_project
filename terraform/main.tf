terraform {
  backend "s3" {
    bucket = "ckc101-13-bucket-name-12345"
    key    = "terraform/state"
    region = "ap-northeast-1"
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

provider "google" {
  project = "ckc101-13"
  region  = "asia-east1"
}

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
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.enable_compute ? 1 : 0
  name     = google_cloud_run_v2_service.app[0].name
  location = google_cloud_run_v2_service.app[0].location
  role     = "roles/run.invoker"
  member   = "allUsers"
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

resource "google_service_account_iam_member" "jenkins_wif_binding" {
  service_account_id = google_service_account.jenkins_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.jenkins.name}/*"
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
