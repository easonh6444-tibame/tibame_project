# CI/CD 流水線架構

## 全景流程圖

```
┌────────────────────────────────────────────────────────────────────────────┐
│ ① 開發 / 版控（GitLab @192.168.0.10）   角色：programmer / develop / PM / devops │
└────────────────────────────────────────────────────────────────────────────┘

   programmer / develop
        │  push feature branch（main 受保護，push=No one）
        │  開 Merge Request
        ▼
  ╔══════════════════════════════════════════════════════════════╗
  ║  GitLab ↔ Jenkins 同步（gitlab-branch-source plugin）          ║
  ║  webhook / scan → 探索 MR → 自動建立 MR-N job                  ║
  ║  憑證：PersonalAccessToken（API + git checkout 共用）          ║
  ╚══════════════════════════════════════════════════════════════╝
        │
        ▼
  ┌──────────────────────────────────────┐
  │ Jenkins：PR 測試（只測容器）           │
  │   Checkout → Build → Test             │
  │   Push / Deploy 全部 skip             │
  └──────────────────────────────────────┘
        │
   ┌────┴───────────────────────┐
 測試失敗                     測試通過
   │                            │
   ▼                            ▼
 GitLab MR 標記 failed     GitLab MR 標記 success
 （門檻擋住，不能 merge）   + Discord「📬 PR 已開啟（測試通過）」
                                │
                                ▼
                   ┌────────────────────────────┐
                   │ GitLab 合併門檻             │
                   │ only_allow_merge_if_        │
                   │ pipeline_succeeds = true    │
                   └────────────────────────────┘
                                │  只有 PM(Maintainer) 能 merge
                                ▼
                          PM merge → main
                                │
┌───────────────────────────────┼────────────────────────────────────────────┐
│ ② main 部署流程（Jenkins）      ▼                                            │
└────────────────────────────────────────────────────────────────────────────┘
        Checkout → Build → Test → Push（本地 registry :5000）
                          │   Discord 進度訊息即時更新（單一訊息編輯）
                          ▼
               ┌───────────────────────────┐
               │ 🔒 devops 審批（input）     │ ◄── 只有 devops 或 admin 能按
               │   Deploy / Abort           │
               └───────────────────────────┘
                          │ 核准
                          ▼
        AWS OIDC（assume-role）+ GCP WIF（token 交換）取臨時憑證
                          │
        terraform apply ①：先建 registry（ECR + Artifact Registry）
                          │
        push image → ECR + GAR
                          │
        terraform apply ②：部署運算/網路
          ECS · Cloud Run · LB(固定IP) · Cloudflare DNS
                          │
                          ▼  Discord「🎉 部署成功」
┌────────────────────────────────────────────────────────────────────────────┐
│ ③ 雲端部署結果                                                               │
│                                                                              │
│   AWS:  ECR ──► ECS Fargate (myfirstweb-service)                            │
│                                                                              │
│   GCP:  Artifact Registry ──► Cloud Run (myfirstweb) ◄── GCS（股票歷史持久化）│
│                                     ▲                                         │
│   使用者 ─► https://buy0050.xyz ─► Cloudflare DNS (A → 34.8.85.156, 灰雲)    │
│                                     │                                         │
│                                     ▼                                         │
│                          GCP HTTPS LB (固定 IP, 託管憑證)                     │
│                                     │                                         │
│                                     ▼                                         │
│                          serverless NEG ──► Cloud Run ──► 0050 儀表板        │
└────────────────────────────────────────────────────────────────────────────┘
```

## 三道守門機制

| 關卡 | 機制 | 誰能過 |
|---|---|---|
| **合併程式碼** | GitLab MR + 分支保護（main push=No one） | 只有 **PM** 能 merge |
| **合併前必須過測試** | gitlab-branch-source 回報狀態 + `only_allow_merge_if_pipeline_succeeds` | pipeline 綠燈才開放 merge |
| **部署上雲** | Jenkins `input`（`submitter 'devops'` + `beforeInput true`） | 只有 **devops**/admin 能核准 |

## GitLab ↔ Jenkins 同步（這次新增）

- **Plugin**：`gitlab-branch-source`（+ `gitlab-api`）
- **Jenkins 設定**：GitLab server `gitlab-local`（http://192.168.0.10），憑證 `gitlab-pat-token`（**PersonalAccessToken 型別**，同時供 API 的 PRIVATE-TOKEN 與 git checkout）
- **Multibranch source**：`GitLabSCMSource`，traits = BranchDiscovery(1) + OriginMergeRequestDiscovery(1)
- **行為**：開/更新 MR → 自動建 `MR-N` job 只跑 Build+Test → 結果回報 GitLab MR（head_pipeline）→ 門檻擋 merge
- **Discord**：MR 不印逐步進度，只在**測試通過後**送一則「PR 已開啟」；main/dev 才有即時進度訊息

## 角色與權限

| 角色 | GitLab | Jenkins |
|---|---|---|
| **programmer / develop** | Developer（推 feature branch、開 MR） | 無帳號（看 Jenkins 需另開） |
| **PM** | Maintainer（唯一能 merge main） | 無帳號 |
| **devops** | Developer | 有帳號，受限（讀/觸發/取消/**核准部署**，非管理員） |
| admin / root | Owner | Administer（完整） |

## 相關資源

- **App**：0050（元大台灣50）即時股價儀表板，Flask，port 19191，健康檢查 `/api/status`，股價來源 Yahoo Finance（TWSE 擋雲端 IP），歷史存 GCS
- **正式網址**：https://buy0050.xyz
- **Jenkins**：https://jenkins.buy0050.xyz （需登入；`/oidc` 端點公開供雲端聯合驗證）
- **GitLab 註冊**：已關閉（只有管理員能建帳號）
