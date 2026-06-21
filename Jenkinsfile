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

        // main branch → placeholder for cloud deployment
        stage('Deploy to Cloud') {
            when { branch 'main' }
            steps {
                echo "TODO: deploy ${IMAGE}:${TAG} to cloud (AWS/GCP)"
            }
        }
    }

    post {
        success { echo "✅ Build ${TAG} (${env.BRANCH_NAME}) deployed successfully" }
        failure { echo "❌ Build ${TAG} (${env.BRANCH_NAME}) failed" }
        always  { sh "docker rmi ${IMAGE}:${TAG} || true" }
    }
}
