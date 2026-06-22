# CI/CD 流水線流程

## 整體流程圖

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ① 開發 / 版控（GitLab @192.168.0.10）                                          │
└─────────────────────────────────────────────────────────────────────────────┘

  programmer / develop / devops          PM (Maintainer)
        │ push 到 feature branch              │
        │ 開 Merge Request ───────────────►  │ 只有 PM 能 merge
        │ (main 受保護: push=No one)          ▼
        │                              merge 進 main ✅
        └──────────────────────────────────┬──
                                            │ (推到 main)
                                            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ ② Jenkins Multibranch Pipeline (tibame_project)  ※需登入才看得到              │
└─────────────────────────────────────────────────────────────────────────────┘
                                            │
                      ┌─────────────────────┴─────────────────────┐
                      ▼
            ┌──────────────────┐
            │ Checkout (SCM)   │
            └────────┬─────────┘
                     ▼
            ┌──────────────────┐
            │ Build            │  docker build → 192.168.0.10:5000/tibame_project
            └────────┬─────────┘
                     ▼
            ┌──────────────────┐
            │ Test             │  跑容器 + curl /api/status 健康檢查
            └────────┬─────────┘
                     ▼
            ┌──────────────────┐
            │ Push             │  push image 到本地 registry (:5000)
            └────────┬─────────┘
                     ▼
        ┌────────────┴─────────────┐  依分支分流 (when)
        ▼                          ▼
  ┌───────────────┐        ┌──────────────────────────┐
  │ branch = dev  │        │ branch = main            │
  │ Deploy to Test│        │ Deploy to Cloud          │
  │ SSH→192.168.  │        │                          │
  │ 0.65 docker run│       │  ┌────────────────────┐  │
  └───────────────┘        │  │ 🔒 input 審批關卡   │  │  ◄── 暫停！
                           │  │ 只有 devops 能按    │  │      build 完成
                           │  │ [Deploy] / [Abort] │  │      等 devops 核准
                           │  └─────────┬──────────┘  │
                           │            ▼ (devops 核准) │
                           │  AWS OIDC assume-role     │  ← Jenkins OIDC
                           │  GCP WIF token exchange   │    (jenkins.buy0050.xyz/oidc)
                           │            │              │
                           │  terraform apply ①        │  建 registry
                           │   (ECR + Artifact Reg)    │
                           │            │              │
                           │  push image → ECR         │  AWS
                           │  push image → GAR         │  GCP
                           │            │              │
                           │  terraform apply ②        │  部署運算+網路
                           │   ECS / Cloud Run /       │
                           │   LB+固定IP / Cloudflare  │
                           │   DNS                     │
                           └────────────┬──────────────┘
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ ③ post：Discord 通知 (Jenkins credential 存 webhook)                          │
│   ✅ success  /  ❌ failure  /  ⚠️ aborted(未核准)  →  Discord 頻道           │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ ④ 部署結果（雲端）                                                            │
│                                                                               │
│   AWS:  ECR ──► ECS Fargate (myfirstweb-service)                             │
│                                                                               │
│   GCP:  Artifact Registry ──► Cloud Run (myfirstweb, asia-east1)             │
│                                     ▲                                          │
│   使用者 ──► https://buy0050.xyz ──► Cloudflare DNS (A→34.8.85.156, 灰雲)     │
│                                     │                                          │
│                                     ▼                                          │
│                          GCP HTTPS LB (固定IP 34.8.85.156, 託管憑證)          │
│                                     │                                          │
│                                     ▼                                          │
│                          serverless NEG ──► Cloud Run ──► 0050 儀表板         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 重點摘要

| 階段 | 機制 | 守門 |
|---|---|---|
| **合併程式** | GitLab MR | 只有 **PM** 能 merge 到 main |
| **部署上雲** | Jenkins `input` | 只有 **devops** 能核准 |
| **CI 認證** | Jenkins OIDC + WIF | 無長期金鑰，臨時 token |
| **部署順序** | 兩段 terraform | 先建 registry→push image→再部署（避免 Cloud Run「Image not found」） |
| **網域** | Cloudflare provider (IaC) | DNS 自動指向 GCP LB 固定 IP |
| **通知** | Discord webhook | 成功/失敗/中止都通知 |
| **可見性** | Jenkins 關閉匿名讀取 | 需登入才能看 build |

## 角色與權限

| 角色 | GitLab | Jenkins |
|---|---|---|
| **programmer / develop** | Developer（推 feature branch、開 MR） | 預設無帳號 |
| **PM** | Maintainer（唯一能 merge main） | 預設無帳號 |
| **devops** | Developer | 有帳號，**唯一能核准部署** |

## 相關資源

- **App**：0050（元大台灣50）即時股價儀表板，Flask，port 19191，健康檢查 `/api/status`
- **正式網址**：https://buy0050.xyz
- **Jenkins**：https://jenkins.buy0050.xyz （需登入；`/oidc` 端點公開供雲端聯合驗證）
- **OIDC issuer**：`https://jenkins.buy0050.xyz/oidc`（Jenkins OIDC plugin；dex/vault 已淘汰）
