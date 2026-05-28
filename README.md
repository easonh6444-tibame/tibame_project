# 🚀 Flask App — Docker & AWS 部署指南

## 📁 專案結構

```
antigravity/
├── docker-compose.yml          ← 本地 & EC2 上啟動用
├── deploy_aws.sh               ← Linux/Mac 一鍵部署腳本
├── deploy_aws.ps1              ← Windows PowerShell 一鍵部署腳本
└── first_project/
    ├── Dockerfile              ← 多階段建置，使用 Gunicorn
    ├── .dockerignore
    ├── requirements.txt        ← 含 Flask + Gunicorn
    ├── run.py                  ← 應用程式入口
    └── src/
        ├── app.py
        └── templates/
```

---

## ✅ 第一步：本地測試 Docker

```bash
# 在 antigravity/ 目錄下執行
docker compose up --build
```

瀏覽器開啟 → **http://localhost:19191**

---

## ☁️ 第二步：部署到 AWS

### 事前準備

| 項目 | 說明 |
|------|------|
| AWS CLI | `aws configure` 設定 Access Key / Secret |
| Docker Desktop | 本地建置 image 用 |
| ECR Repository | 在 AWS Console 建立（名稱：`first-project-web`）|
| EC2 Instance | 建議 Amazon Linux 2023，t2.micro (Free Tier) |
| EC2 安全群組 | 開放 **port 19191**（Inbound TCP） |
| EC2 上安裝 Docker | 見下方 EC2 初始化指令 |

### EC2 初始化（第一次 SSH 進去執行）

```bash
# Amazon Linux 2023
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user

# 安裝 Docker Compose plugin
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 安裝 AWS CLI（若尚未安裝）
sudo dnf install -y awscli

# 設定 EC2 IAM Role 或執行 aws configure
aws configure
```

### ECR Repository 建立（只需一次）

```bash
aws ecr create-repository \
  --repository-name first-project-web \
  --region ap-northeast-1
```

### 執行部署腳本

**Windows（PowerShell）：**
```powershell
# 1. 先編輯 deploy_aws.ps1，填入你的 AWS_ACCOUNT_ID、EC2_HOST、EC2_KEY
# 2. 執行
.\deploy_aws.ps1
```

**Linux / Mac：**
```bash
chmod +x deploy_aws.sh
./deploy_aws.sh
```

---

## 🔐 EC2 安全群組設定

在 AWS Console → EC2 → Security Groups → 你的群組 → Inbound rules：

| Type | Protocol | Port | Source |
|------|----------|------|--------|
| Custom TCP | TCP | **19191** | 0.0.0.0/0 |
| SSH | TCP | 22 | 你的 IP |

---

## 🔄 常用 Docker Compose 指令

```bash
# 啟動（背景執行）
docker compose up -d

# 查看 log
docker compose logs -f web

# 停止
docker compose down

# 重建 image 並重啟
docker compose up -d --build
```

---

## 🌐 API 端點

| 方法 | 路徑 | 說明 |
|------|------|------|
| GET | `/` | 主頁面 |
| GET | `/api/status` | 伺服器狀態 |
| GET | `/api/tasks` | 取得所有任務 |
| POST | `/api/tasks` | 新增任務 |
| PATCH | `/api/tasks/<id>` | 更新任務狀態 |
| DELETE | `/api/tasks/<id>` | 刪除任務 |