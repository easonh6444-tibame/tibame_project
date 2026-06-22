// Discord 即時進度通知：先建立一則訊息(?wait=true 取得 message id)，之後 PATCH 編輯同一則，
// 讓單一訊息隨 pipeline 即時更新。用 curl 發送（python urllib 會被 Discord 的 Cloudflare 擋）。
def discordSend(String content) {
    withCredentials([string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK')]) {
        withEnv(["DISCORD_MSG=${content}"]) {
            sh '''
                python3 -c "import json,os; open('dc.json','w',encoding='utf-8').write(json.dumps({'content': os.environ['DISCORD_MSG']}))"
                curl -sf -H "Content-Type: application/json" --data @dc.json "${DISCORD_WEBHOOK}?wait=true" -o dc_resp.json || true
                python3 -c "import json; print(json.load(open('dc_resp.json')).get('id',''))" > .discord_mid 2>/dev/null || echo "" > .discord_mid
                rm -f dc.json dc_resp.json
            '''
        }
    }
}

def discordEdit(String content) {
    withCredentials([string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK')]) {
        withEnv(["DISCORD_MSG=${content}"]) {
            sh '''
                MID=$(cat .discord_mid 2>/dev/null || echo "")
                python3 -c "import json,os; open('dc.json','w',encoding='utf-8').write(json.dumps({'content': os.environ['DISCORD_MSG']}))"
                if [ -n "$MID" ]; then
                    curl -sf -X PATCH -H "Content-Type: application/json" --data @dc.json "${DISCORD_WEBHOOK}/messages/${MID}" || true
                else
                    curl -sf -H "Content-Type: application/json" --data @dc.json "${DISCORD_WEBHOOK}" || true
                fi
                rm -f dc.json
            '''
        }
    }
}

def progHeader() {
    def sha = (env.GIT_COMMIT ?: '').take(7)
    return "**🔧 Build #${env.BUILD_NUMBER} · ${env.BRANCH_NAME}**" + (sha ? " `${sha}`" : "")
}
// MR(PR) 建置不印進度（env.CHANGE_ID 有值代表是 MR）；只在開啟時送一則通知
def progStart(String body) { if (env.CHANGE_ID) return; discordSend(progHeader() + "\n" + body + "\n" + env.BUILD_URL) }
def prog(String body)      { if (env.CHANGE_ID) return; discordEdit(progHeader() + "\n" + body + "\n" + env.BUILD_URL) }

// 純送一則訊息（不追蹤 id、不編輯）
def discordSimple(String content) {
    withCredentials([string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK')]) {
        withEnv(["DISCORD_MSG=${content}"]) {
            sh '''
                python3 -c "import json,os; open('dc.json','w',encoding='utf-8').write(json.dumps({'content': os.environ['DISCORD_MSG']}))"
                curl -sf -H "Content-Type: application/json" --data @dc.json "${DISCORD_WEBHOOK}" || true
                rm -f dc.json
            '''
        }
    }
}
def notifyPrOpened() {
    def title = env.CHANGE_TITLE ? (" — " + env.CHANGE_TITLE) : ""
    discordSimple("📬 **PR !${env.CHANGE_ID} 已開啟**（測試通過 ✅，可供審核）" + title +
        "\n作者: " + (env.CHANGE_AUTHOR ?: '?') + " ｜ 目標分支: " + (env.CHANGE_TARGET ?: 'main') +
        "\n" + (env.CHANGE_URL ?: env.BUILD_URL))
}

pipeline {
    agent any

    environment {
        REGISTRY = "192.168.0.10:5000"
        IMAGE    = "${REGISTRY}/tibame_project"
        TAG      = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                // MR 不在此通知（等測試通過後才在 post 通知）；main/dev 才開始即時進度
                script { if (!env.CHANGE_ID) progStart("✅ Checkout\n⏳ Build…") }
            }
        }

        stage('Build') {
            steps {
                sh "docker build -t ${IMAGE}:${TAG} -t ${IMAGE}:latest ./first_project"
            }
            post { success { script { prog("✅ Checkout　✅ Build\n⏳ Test…") } } }
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
                success { script { prog("✅ Checkout　✅ Build　✅ Test\n⏳ Push…") } }
                failure { sh "docker rm -f test-${TAG} || true" }
            }
        }

        stage('Push') {
            // MR(change request) 只跑到 Build+Test 當作 PR 測試；只有 main/dev 才 push + 部署
            when { anyOf { branch 'main'; branch 'dev' } }
            steps {
                sh "docker push ${IMAGE}:${TAG}"
                sh "docker push ${IMAGE}:latest"
            }
            post {
                success {
                    script {
                        if (env.BRANCH_NAME == 'main') {
                            prog("✅ Checkout　✅ Build　✅ Test　✅ Push\n⏳ 等待 devops 核准部署…")
                        } else {
                            prog("✅ Checkout　✅ Build　✅ Test　✅ Push")
                        }
                    }
                }
            }
        }

        // dev branch → deploy to test server (192.168.0.65)
        stage('Deploy to Test') {
            when { branch 'dev' }
            steps {
                script { prog("✅ Checkout　✅ Build　✅ Test　✅ Push\n🚀 部署到測試機 (192.168.0.65)…") }
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
            // beforeInput：先判斷分支再決定要不要問審批，否則 MR 也會被要求核准
            when {
                branch 'main'
                beforeInput true
            }
            // 部署前需 devops 手動核准（只有 devops 或管理員能按）
            input {
                message 'Build 已完成，是否部署到雲端？'
                ok 'Deploy'
                submitter 'devops'
                submitterParameter 'APPROVER'
            }
            environment {
                AWS_ROLE_ARN     = credentials('aws-jenkins-role-arn')
                AWS_REGION       = "ap-northeast-1"
                AWS_ECR_REGISTRY = "112064333943.dkr.ecr.ap-northeast-1.amazonaws.com"
                ECR_IMAGE        = "${AWS_ECR_REGISTRY}/myfirstweb"
                GCP_PROJECT      = "ckc101-13"
                GCP_REGION       = "asia-east1"
                GAR_IMAGE        = "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/myfirstweb/myfirstweb"
                GCP_WIF_PROVIDER = credentials('gcp-wif-provider')
                GCP_SA_EMAIL     = credentials('gcp-sa-email')
            }
            steps {
                script { prog("✅ Checkout　✅ Build　✅ Test　✅ Push\n🚀 部署到雲端中 (ECS + Cloud Run)…") }
                withCredentials([
                    string(credentialsId: 'jenkins-oidc-aws', variable: 'JWT_AWS'),
                    string(credentialsId: 'jenkins-oidc-gcp', variable: 'JWT_GCP'),
                    string(credentialsId: 'cloudflare-api-token', variable: 'CLOUDFLARE_API_TOKEN')
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

# ── 2. GCP: exchange JWT via Workload Identity Federation ──
GCP_RESP=$(python3 -c "
import json, urllib.request, sys
payload = {
    'grantType': 'urn:ietf:params:oauth:grant-type:token-exchange',
    'audience': '//iam.googleapis.com/${GCP_WIF_PROVIDER}',
    'subjectTokenType': 'urn:ietf:params:oauth:token-type:id_token',
    'requestedTokenType': 'urn:ietf:params:oauth:token-type:access_token',
    'subjectToken': '${JWT_GCP}',
    'scope': 'https://www.googleapis.com/auth/cloud-platform'
}
req = urllib.request.Request('https://sts.googleapis.com/v1/token',
    data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'})
try:
    resp = urllib.request.urlopen(req)
    print(resp.read().decode())
except urllib.error.HTTPError as e:
    print(e.read().decode(), file=sys.stderr)
    sys.exit(1)
")
GCP_TOKEN=$(echo "${GCP_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

SA_RESP=$(curl -sf -X POST \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${GCP_SA_EMAIL}:generateAccessToken" \
  -H "Authorization: Bearer ${GCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"scope":["https://www.googleapis.com/auth/cloud-platform"]}')
echo "SA token response: ${SA_RESP}"
SA_TOKEN=$(echo "${SA_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin)['accessToken'])")

# ── 3. Terraform: create registries first (ECR + Artifact Registry) ──
# Cloud Run 部署時會驗證 image 是否存在，所以必須先有 registry 且 image 已 push，
# 再 apply 運算資源，否則會 "Image not found"。
export GOOGLE_OAUTH_ACCESS_TOKEN="${SA_TOKEN}"
cd terraform
terraform init -input=false
terraform apply -input=false -auto-approve \
  -var="enable_compute=true" \
  -var="app_image_tag=${TAG}" \
  -target=aws_ecr_repository.app \
  -target=google_artifact_registry_repository.app
cd ..

# ── 4. Push images to ECR ──
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ECR_REGISTRY}
docker tag ${IMAGE}:${TAG} ${ECR_IMAGE}:${TAG}
docker tag ${IMAGE}:${TAG} ${ECR_IMAGE}:latest
docker push ${ECR_IMAGE}:${TAG}
docker push ${ECR_IMAGE}:latest

# ── 5. Push images to GCP Artifact Registry ──
docker login -u oauth2accesstoken -p "${SA_TOKEN}" ${GCP_REGION}-docker.pkg.dev
docker tag ${IMAGE}:${TAG} ${GAR_IMAGE}:${TAG}
docker tag ${IMAGE}:${TAG} ${GAR_IMAGE}:latest
docker push ${GAR_IMAGE}:${TAG}
docker push ${GAR_IMAGE}:latest

# ── 6. Terraform: deploy compute (images now exist in both registries) ──
cd terraform
terraform apply -input=false -auto-approve \
  -var="enable_compute=true" \
  -var="app_image_tag=${TAG}" \
  -target=aws_ecs_cluster.app \
  -target=aws_ecs_task_definition.app \
  -target=aws_ecs_service.app \
  -target=google_cloud_run_v2_service.app \
  -target=google_cloud_run_v2_service_iam_member.public \
  -target=google_compute_region_network_endpoint_group.app \
  -target=google_compute_backend_service.app \
  -target=google_compute_url_map.app \
  -target=google_compute_managed_ssl_certificate.app \
  -target=google_compute_target_https_proxy.app \
  -target=google_compute_global_address.app \
  -target=google_compute_global_forwarding_rule.https \
  -target=google_compute_url_map.https_redirect \
  -target=google_compute_target_http_proxy.app \
  -target=google_compute_global_forwarding_rule.http \
  -target=cloudflare_record.app
cd ..
unset GOOGLE_OAUTH_ACCESS_TOKEN
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
'''
                }
            }
        }
    }

    post {
        success {
            echo "✅ Build ${TAG} (${env.BRANCH_NAME}) succeeded"
            script {
                if (env.CHANGE_ID) {
                    notifyPrOpened()   // MR：測試通過後才通知「PR 已開啟」
                } else {
                    prog("✅ Checkout　✅ Build　✅ Test　✅ Push　✅ Deploy\n🎉 **部署成功**")
                }
            }
        }
        failure {
            echo "❌ Build ${TAG} (${env.BRANCH_NAME}) failed"
            script { prog("❌ **Build 失敗** — 查看 log 連結") }
        }
        aborted {
            script { prog("⚠️ **中止／未核准部署**") }
        }
        always  { sh "docker rmi ${IMAGE}:${TAG} || true" }
    }
}
