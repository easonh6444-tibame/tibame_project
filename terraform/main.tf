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

resource "aws_s3_bucket" "tfstate" {
  bucket = "ckc101-13-bucket-name-12345"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "myfirstweb"
  image_tag_mutability = "MUTABLE"
}

# ── GCP ──────────────────────────────────────────

resource "google_artifact_registry_repository" "app" {
  repository_id = "myfirstweb"
  location      = "asia-east1"
  format        = "DOCKER"
}

resource "google_cloud_run_v2_service" "app" {
  name     = "myfirstweb"
  location = "asia-east1"

  template {
    containers {
      image = "asia-east1-docker.pkg.dev/ckc101-13/myfirstweb/myfirstweb:latest"
      ports {
        container_port = 19191
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.app.name
  location = google_cloud_run_v2_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
