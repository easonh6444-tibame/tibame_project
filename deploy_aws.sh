#!/usr/bin/env bash
# =============================================================================
#  deploy_aws.sh  ──  Build → Push to ECR → Deploy on EC2 via SSH
#
#  Usage:
#    chmod +x deploy_aws.sh
#    ./deploy_aws.sh
#
#  Prerequisites (fill in the variables below):
#    - AWS CLI installed & configured  (aws configure)
#    - Docker installed locally
#    - An ECR repository already created
#    - An EC2 instance with Docker + Docker Compose installed
#    - SSH key pair for EC2 access
# =============================================================================
set -euo pipefail

# ── 請修改以下變數 ──────────────────────────────────────────────────────────
AWS_REGION="ap-northeast-1"                         # 你的 AWS 區域
AWS_ACCOUNT_ID="123456789012"                       # 你的 12 位 AWS 帳號 ID
ECR_REPO_NAME="first-project-web"                   # ECR Repository 名稱
IMAGE_TAG="latest"

EC2_HOST="ec2-xx-xx-xx-xx.ap-northeast-1.compute.amazonaws.com"  # EC2 公開 DNS
EC2_USER="ec2-user"                                 # Amazon Linux → ec2-user / Ubuntu → ubuntu
EC2_KEY="~/.ssh/your-key.pem"                       # 你的 .pem 金鑰路徑
REMOTE_DIR="/home/${EC2_USER}/first_project"        # EC2 上的部署目錄
# ───────────────────────────────────────────────────────────────────────────

ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FULL_IMAGE="${ECR_URI}/${ECR_REPO_NAME}:${IMAGE_TAG}"

echo "============================================================"
echo " Step 1 / 4 : Build Docker image"
echo "============================================================"
docker build -t "${ECR_REPO_NAME}:${IMAGE_TAG}" ./first_project

echo "============================================================"
echo " Step 2 / 4 : Authenticate & push to ECR"
echo "============================================================"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_URI}"

docker tag "${ECR_REPO_NAME}:${IMAGE_TAG}" "${FULL_IMAGE}"
docker push "${FULL_IMAGE}"

echo "============================================================"
echo " Step 3 / 4 : Copy docker-compose.yml to EC2"
echo "============================================================"
ssh -i "${EC2_KEY}" -o StrictHostKeyChecking=no \
    "${EC2_USER}@${EC2_HOST}" "mkdir -p ${REMOTE_DIR}"

scp -i "${EC2_KEY}" -o StrictHostKeyChecking=no \
    docker-compose.yml "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/docker-compose.yml"

echo "============================================================"
echo " Step 4 / 4 : Pull & restart containers on EC2"
echo "============================================================"
ssh -i "${EC2_KEY}" -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" \
    "cd ${REMOTE_DIR} && \
     aws ecr get-login-password --region ${AWS_REGION} \
       | docker login --username AWS --password-stdin ${ECR_URI} && \
     IMAGE_TAG=${IMAGE_TAG} ECR_URI=${ECR_URI} ECR_REPO_NAME=${ECR_REPO_NAME} \
     docker compose pull && \
     docker compose up -d --remove-orphans"

echo ""
echo "✅  Deployment complete!"
echo "   App is running at  http://${EC2_HOST}:19191"
