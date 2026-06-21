pipeline {
    agent any

    environment {
        REGISTRY = "192.168.0.10:5000"
        IMAGE    = "${REGISTRY}/tibame_project"
        TAG      = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Build') {
            steps {
                sh "docker build -t ${IMAGE}:${TAG} -t ${IMAGE}:latest ./first_project"
            }
        }

        stage('Test') {
            steps {
                sh """
                    docker run -d --name test-${TAG} --network jenkins_default ${IMAGE}:${TAG}
                    CONTAINER_IP=\$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' test-${TAG})
                    for i in \$(seq 1 15); do
                        curl -sf http://\${CONTAINER_IP}:19191/api/status && break
                        echo "Waiting... \${i}/15"
                        sleep 2
                    done
                    curl -f http://\${CONTAINER_IP}:19191/api/status
                    docker rm -f test-${TAG}
                """
            }
            post {
                failure { sh "docker rm -f test-${TAG} || true" }
            }
        }

        stage('Push') {
            steps {
                sh "docker push ${IMAGE}:${TAG}"
                sh "docker push ${IMAGE}:latest"
            }
        }

        // dev branch → deploy to test server (192.168.0.65)
        stage('Deploy to Test') {
            when { branch 'dev' }
            steps {
                sshagent(['test-server-ssh']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no root@192.168.0.65 '
                            docker pull ${IMAGE}:${TAG} &&
                            docker rm -f tibame_app || true &&
                            docker run -d --name tibame_app --restart=unless-stopped -p 19191:19191 ${IMAGE}:${TAG}
                        '
                    """
                }
            }
        }

        // main branch → deploy to AWS (ECR+ECS) and GCP (Artifact Registry+Cloud Run) via Jenkins OIDC
        stage('Deploy to Cloud') {
            when { branch 'main' }
            environment {
                AWS_ROLE_ARN     = credentials('aws-jenkins-role-arn')
                AWS_REGION       = "ap-northeast-1"
                AWS_ECR_REGISTRY = "992382492557.dkr.ecr.ap-northeast-1.amazonaws.com"
                ECR_IMAGE        = "${AWS_ECR_REGISTRY}/myfirstweb"
                GCP_PROJECT      = "ckc101-13"
                GCP_REGION       = "asia-east1"
                GAR_IMAGE        = "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/myfirstweb/myfirstweb"
                GCP_WIF_PROVIDER = credentials('gcp-wif-provider')
                GCP_SA_EMAIL     = credentials('gcp-sa-email')
            }
            steps {
                withCredentials([
                    string(credentialsId: 'jenkins-oidc-aws', variable: 'JWT_AWS'),
                    string(credentialsId: 'jenkins-oidc-gcp', variable: 'JWT_GCP')
                ]) {
                    sh '''#!/bin/bash
set -euo pipefail

# ── 1. AWS: assume role with Jenkins OIDC token ──
CREDS=$(aws sts assume-role-with-web-identity \
  --role-arn "${AWS_ROLE_ARN}" \
  --role-session-name jenkins-${BUILD_NUMBER} \
  --web-identity-token "${JWT_AWS}" \
  --duration-seconds 3600 \
  --query 'Credentials' --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SessionToken'])")

aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ECR_REGISTRY}
docker tag ${IMAGE}:${TAG} ${ECR_IMAGE}:${TAG}
docker tag ${IMAGE}:${TAG} ${ECR_IMAGE}:latest
docker push ${ECR_IMAGE}:${TAG}
docker push ${ECR_IMAGE}:latest

aws ecs update-service --cluster default --service myfirstweb-service \
  --force-new-deployment --region ${AWS_REGION} > /dev/null

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# ── 2. GCP: exchange JWT via Workload Identity Federation ──
GCP_TOKEN=$(curl -sf -X POST "https://sts.googleapis.com/v1/token" \
  -H "Content-Type: application/json" \
  -d "{
    \"grantType\": \"urn:ietf:params:oauth:grant-type:token-exchange\",
    \"audience\": \"//iam.googleapis.com/${GCP_WIF_PROVIDER}\",
    \"subjectTokenType\": \"urn:ietf:params:oauth:token-type:id_token\",
    \"requestedTokenType\": \"urn:ietf:params:oauth:token-type:access_token\",
    \"subjectToken\": \"${JWT_GCP}\",
    \"scope\": \"https://www.googleapis.com/auth/cloud-platform\"
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Impersonate SA to get a scoped token
SA_TOKEN=$(curl -sf -X POST \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${GCP_SA_EMAIL}:generateAccessToken" \
  -H "Authorization: Bearer ${GCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"scope":["https://www.googleapis.com/auth/cloud-platform"]}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])")

docker login -u oauth2accesstoken -p "${SA_TOKEN}" ${GCP_REGION}-docker.pkg.dev
docker tag ${IMAGE}:${TAG} ${GAR_IMAGE}:${TAG}
docker tag ${IMAGE}:${TAG} ${GAR_IMAGE}:latest
docker push ${GAR_IMAGE}:${TAG}
docker push ${GAR_IMAGE}:latest

gcloud run services update myfirstweb \
  --image ${GAR_IMAGE}:${TAG} \
  --region ${GCP_REGION} \
  --project ${GCP_PROJECT} \
  --access-token-file <(echo ${SA_TOKEN})
'''
                }
            }
        }
    }

    post {
        success { echo "✅ Build ${TAG} (${env.BRANCH_NAME}) deployed successfully" }
        failure { echo "❌ Build ${TAG} (${env.BRANCH_NAME}) failed" }
        always  { sh "docker rmi ${IMAGE}:${TAG} || true" }
    }
}
