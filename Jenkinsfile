// All Discord notifications use embeds.
// main/dev builds track progress via a single editable embed.
// MR builds are silent during pipeline — one embed fires only after tests pass.
// color: 3447003=blue(running)  3066993=green(ok)  15158332=red(fail)  15105570=orange

// Build the embed payload Map from opts (title/description/url/color/fields).
def buildEmbed(Map opts) {
    def embed = [color: (opts.color ?: 3447003)]
    if (opts.title)       embed.title       = opts.title
    if (opts.description) embed.description = opts.description
    if (opts.url)         embed.url         = opts.url
    if (opts.fields)      embed.fields      = opts.fields
    return embed
}

// Send a one-shot embed (no later edits).
def discordEmbed(Map opts) {
    withCredentials([string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK')]) {
        writeFile(file: 'dc.json', text: groovy.json.JsonOutput.toJson([embeds: [buildEmbed(opts)]]), encoding: 'UTF-8')
        sh 'curl -sf -H "Content-Type: application/json" --data @dc.json "${DISCORD_WEBHOOK}" || true; rm -f dc.json'
    }
}

// Send an embed and remember its message id so it can be edited later.
def discordSendEmbed(Map opts) {
    withCredentials([string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK')]) {
        writeFile(file: 'dc.json', text: groovy.json.JsonOutput.toJson([embeds: [buildEmbed(opts)]]), encoding: 'UTF-8')
        def resp = sh(returnStdout: true, script: 'curl -sf -H "Content-Type: application/json" --data @dc.json "${DISCORD_WEBHOOK}?wait=true" || echo "{}"').trim()
        sh 'rm -f dc.json'
        def mid = ''
        try { mid = new groovy.json.JsonSlurper().parseText(resp)?.id ?: '' } catch (ignored) {}
        writeFile(file: '.discord_mid', text: mid, encoding: 'UTF-8')
    }
}

// Edit the previously-sent embed (falls back to a new message if no id stored).
def discordEditEmbed(Map opts) {
    withCredentials([string(credentialsId: 'discord-webhook-url', variable: 'DISCORD_WEBHOOK')]) {
        writeFile(file: 'dc.json', text: groovy.json.JsonOutput.toJson([embeds: [buildEmbed(opts)]]), encoding: 'UTF-8')
        def mid = ''
        try { mid = readFile('.discord_mid').trim() } catch (ignored) {}
        if (mid) {
            sh 'curl -sf -X PATCH -H "Content-Type: application/json" --data @dc.json "${DISCORD_WEBHOOK}/messages/' + mid + '" || true'
        } else {
            sh 'curl -sf -H "Content-Type: application/json" --data @dc.json "${DISCORD_WEBHOOK}" || true'
        }
        sh 'rm -f dc.json'
    }
}

def progTitle() {
    def sha = (env.GIT_COMMIT ?: '').take(7)
    return "Build #${env.BUILD_NUMBER} · ${env.BRANCH_NAME}" + (sha ? " ${sha}" : "")
}
def progStart(String msg) {
    if (env.CHANGE_ID) return
    discordSendEmbed([title: progTitle(), description: msg, url: env.BUILD_URL, color: 3447003])
}
def prog(String msg, int color = 3447003) {
    if (env.CHANGE_ID) return
    discordEditEmbed([title: progTitle(), description: msg, url: env.BUILD_URL, color: color])
}

// ── Gemini AI ────────────────────────────────────────────────────────────────

def callGemini(String sys, String user, String fallback = '（AI 分析暫時無法使用）') {
    try {
        withCredentials([string(credentialsId: 'gemini-api-key', variable: 'GEMINI_KEY')]) {
            def payload = groovy.json.JsonOutput.toJson([
                system_instruction: [parts: [[text: sys]]],
                contents          : [[role: 'user', parts: [[text: user]]]],
                generationConfig  : [
                    maxOutputTokens: 1024,
                    thinkingConfig : [thinkingBudget: 0]
                ]
            ])
            writeFile(file: '.gemini_req.json', text: payload, encoding: 'UTF-8')
            def resp = sh(returnStdout: true, script: '''
                curl -sf --max-time 30 \
                  -H "Content-Type: application/json" \
                  --data @.gemini_req.json \
                  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_KEY}"
            ''').trim()
            sh 'rm -f .gemini_req.json'
            def parsed = new groovy.json.JsonSlurper().parseText(resp)
            return parsed.candidates[0].content.parts[0].text.trim()
        }
    } catch (ignored) {
        sh 'rm -f .gemini_req.json || true'
        return fallback
    }
}

// Run after tests pass; fetch diff against target branch and summarise via the Flue agent.
def prDiffSummary() {
    def target = env.CHANGE_TARGET ?: 'main'
    def diff = sh(returnStdout: true, script: """
        git fetch --depth=30 origin ${target} 2>/dev/null || true
        git diff origin/${target}...HEAD | head -c 7000
    """).trim()
    if (!diff) return '（此 PR 無可分析的程式碼變更）'
    return flueSummary(diff)
}

// Summarise a diff with the Flue agent in ci/flue (model google/gemini-2.5-flash via Pi).
// stdout is a single JSON line {"text": "...", ...}; decorative output goes to stderr.
// Falls back to the direct Gemini REST call so an npm/Flue hiccup never blocks the summary.
def flueSummary(String diff) {
    try {
        withCredentials([string(credentialsId: 'gemini-api-key', variable: 'GEMINI_KEY')]) {
            // Write input JSON via Groovy to avoid shell-escaping the diff on the command line.
            writeFile(file: 'ci/flue/.flue_input.json',
                      text: groovy.json.JsonOutput.toJson([message: diff]), encoding: 'UTF-8')
            def out = sh(returnStdout: true, script: '''
                cd ci/flue
                npm ci --no-audit --no-fund >/dev/null 2>&1 || npm install --no-audit --no-fund >/dev/null 2>&1
                GEMINI_API_KEY="${GEMINI_KEY}" ./node_modules/.bin/flue run pr-summary --input "$(cat .flue_input.json)" 2>/dev/null
            ''').trim()
            sh 'rm -f ci/flue/.flue_input.json'
            def text = new groovy.json.JsonSlurper().parseText(out)?.text?.trim()
            if (text) return text
            error 'flue returned empty text'
        }
    } catch (ignored) {
        sh 'rm -f ci/flue/.flue_input.json || true'
        return callGemini(
            '你是資深 DevOps 工程師，請用繁體中文撰寫 PR 審查摘要（限 300 字，不使用 emoji）。\n' +
            '格式：\n### 變更摘要\n（一兩句概述）\n### 主要異動\n（條列，最多 5 點）\n### 需注意\n（潛在風險；若無寫「無特殊風險」）',
            "PR diff：\n\n${diff}"
        )
    }
}

def deployFailureSummary(String logs) {
    return callGemini(
        '你是 DevOps 工程師，請用繁體中文簡潔說明以下部署失敗原因及建議修復方向（限 200 字）。',
        "部署失敗日誌（節錄）：\n\n${logs}"
    )
}

// Extract base URL and URL-encoded project path from CHANGE_URL.
// Must be @NonCPS because the =~ Matcher is not CPS-serializable.
@NonCPS
def parseMrUrl(String changeUrl) {
    def m = changeUrl =~ /^(https?:\/\/[^\/]+)\/(.+?)\/-\/merge_requests\/\d+$/
    if (!m) return null
    return [base: m[0][1] as String, project: (m[0][2] as String).replace('/', '%2F')]
}

// Post a comment on the GitLab MR. Derives project path from CHANGE_URL, which is always
// set by the GitLab Branch Source plugin. Silently skipped if credentials or vars are missing.
def postGitLabMrComment(String body) {
    try {
        def changeUrl = env.CHANGE_URL ?: ''
        def iid       = env.CHANGE_ID  ?: ''
        if (!changeUrl || !iid) return
        def parts = parseMrUrl(changeUrl)
        if (!parts) return
        def base    = parts.base
        def project = parts.project
        withCredentials([string(credentialsId: 'gitlab-api-token', variable: 'GL_TOKEN')]) {
            writeFile(file: '.gl_note.json', text: groovy.json.JsonOutput.toJson([body: body]), encoding: 'UTF-8')
            sh """
                curl -sf -X POST \
                  -H "PRIVATE-TOKEN: \${GL_TOKEN}" \
                  -H "Content-Type: application/json" \
                  --data @.gl_note.json \
                  "${base}/api/v4/projects/${project}/merge_requests/${iid}/notes" || true
                rm -f .gl_note.json
            """
        }
    } catch (ignored) {
        sh 'rm -f .gl_note.json || true'
    }
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
                script { if (!env.CHANGE_ID) progStart("starting...") }
            }
        }

        stage('Build') {
            steps {
                sh "docker build -t ${IMAGE}:${TAG} -t ${IMAGE}:latest ./first_project"
            }
            post { success { script { prog("build done · testing...") } } }
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
                success { script { prog("build done · test done · pushing...") } }
                failure { sh "docker rm -f test-${TAG} || true" }
            }
        }

        stage('Push') {
            when { anyOf { branch 'main'; branch 'dev' } }
            steps {
                sh "docker push ${IMAGE}:${TAG}"
                sh "docker push ${IMAGE}:latest"
            }
            post {
                success {
                    script {
                        if (env.BRANCH_NAME == 'main') {
                            prog("build done · test done · push done · waiting for deploy approval...")
                        } else {
                            prog("build done · test done · push done")
                        }
                    }
                }
            }
        }

        stage('Deploy to Test') {
            when { branch 'dev' }
            steps {
                script { prog("build done · test done · push done · deploying to test (192.168.0.65)...") }
                sshagent(['test-server-ssh']) {
                    sh """#!/bin/bash
set -eo pipefail
ssh -o StrictHostKeyChecking=no root@192.168.0.65 '
    docker pull ${IMAGE}:${TAG} &&
    docker rm -f tibame_app || true &&
    docker run -d --name tibame_app --restart=unless-stopped -p 19191:19191 ${IMAGE}:${TAG}
' 2>&1 | tee .deploy_log
"""
                }
            }
        }

        stage('Deploy to Cloud') {
            when {
                branch 'main'
                beforeInput true
            }
            input {
                message 'Deploy to cloud?'
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
                script { prog("build done · test done · push done · deploying to cloud (ECS + Cloud Run)...") }
                withCredentials([
                    string(credentialsId: 'jenkins-oidc-aws', variable: 'JWT_AWS'),
                    string(credentialsId: 'jenkins-oidc-gcp', variable: 'JWT_GCP'),
                    string(credentialsId: 'cloudflare-api-token', variable: 'CLOUDFLARE_API_TOKEN')
                ]) {
                    sh '''#!/bin/bash
set -euo pipefail
exec > >(tee .deploy_log) 2>&1

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
export GOOGLE_OAUTH_ACCESS_TOKEN="${SA_TOKEN}"
cd terraform
terraform init -input=false
terraform apply -input=false -auto-approve \
  -var="enable_compute=true" \
  -var="app_image_tag=${TAG}" \
  -target=aws_ecr_repository.app \
  -target=google_artifact_registry_repository.app
cd ..

# ── 4. Push to ECR ──
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ECR_REGISTRY}
docker tag ${IMAGE}:${TAG} ${ECR_IMAGE}:${TAG}
docker tag ${IMAGE}:${TAG} ${ECR_IMAGE}:latest
docker push ${ECR_IMAGE}:${TAG}
docker push ${ECR_IMAGE}:latest

# ── 5. Push to GCP Artifact Registry ──
docker login -u oauth2accesstoken -p "${SA_TOKEN}" ${GCP_REGION}-docker.pkg.dev
docker tag ${IMAGE}:${TAG} ${GAR_IMAGE}:${TAG}
docker tag ${IMAGE}:${TAG} ${GAR_IMAGE}:latest
docker push ${GAR_IMAGE}:${TAG}
docker push ${GAR_IMAGE}:latest

# ── 6. Terraform: deploy compute ──
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
            echo "Build ${TAG} (${env.BRANCH_NAME}) passed"
            script {
                if (env.CHANGE_ID) {
                    // MR passed: generate AI summary, send one embed, post GitLab comment
                    def summary = prDiffSummary()
                    discordEmbed([
                        title      : "PR !${env.CHANGE_ID} — tests passed" + (env.CHANGE_TITLE ? " | ${env.CHANGE_TITLE}" : ''),
                        description: summary,
                        color      : 3066993,
                        url        : env.CHANGE_URL ?: env.BUILD_URL,
                        fields     : [
                            [name: 'Author', value: (env.CHANGE_AUTHOR ?: '?'),    inline: true],
                            [name: 'Target', value: (env.CHANGE_TARGET ?: 'main'), inline: true],
                            [name: 'Build',  value: "#${env.BUILD_NUMBER}",        inline: true]
                        ]
                    ])
                    postGitLabMrComment("**AI Code Review** — build #${env.BUILD_NUMBER} passed\n\n${summary}")
                } else {
                    // A deploy ran iff .deploy_log exists — notify deploy success explicitly.
                    def deployed = sh(returnStatus: true, script: "test -s .deploy_log") == 0
                    if (deployed) {
                        def sha = (env.GIT_COMMIT ?: '').take(7)
                        def tgt = (env.BRANCH_NAME == 'main') ? 'cloud (ECS + Cloud Run)' : 'test (192.168.0.65)'
                        prog("build done · test done · push done · deploy done", 3066993)
                        discordEmbed([
                            title      : "Deploy succeeded — ${env.BRANCH_NAME} ${sha}",
                            description: "Deployed to ${tgt}.",
                            color      : 3066993,
                            url        : env.BUILD_URL,
                            fields     : [[name: 'Build', value: "#${env.BUILD_NUMBER}", inline: true]]
                        ])
                    } else {
                        prog("all done.", 3066993)
                    }
                }
            }
        }
        failure {
            echo "Build ${TAG} (${env.BRANCH_NAME}) failed"
            script {
                if (!env.CHANGE_ID) {
                    def hasDeployLog = sh(returnStatus: true, script: "test -s .deploy_log") == 0
                    if (hasDeployLog) {
                        // Deploy failed: read the log, summarise the cause, send a red embed.
                        def logs    = sh(returnStdout: true, script: "tail -80 .deploy_log").trim()
                        def summary = deployFailureSummary(logs)
                        def sha     = (env.GIT_COMMIT ?: '').take(7)
                        prog("deploy failed — see notification", 15158332)
                        discordEmbed([
                            title      : "Deploy failed — ${env.BRANCH_NAME} ${sha}",
                            description: summary,
                            color      : 15158332,
                            url        : env.BUILD_URL,
                            fields     : [[name: 'Build', value: "#${env.BUILD_NUMBER}", inline: true]]
                        ])
                    } else {
                        prog("build/test failed — see logs", 15158332)
                    }
                }
            }
        }
        aborted {
            script { prog("aborted / deploy not approved", 15105570) }
        }
        always {
            sh "docker rmi ${IMAGE}:${TAG} || true"
        }
        // cleanup runs last — AFTER success/failure have read .deploy_log.
        cleanup {
            sh "rm -f .deploy_log .discord_mid || true"
        }
    }
}
