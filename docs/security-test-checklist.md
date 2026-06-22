# 資安權限測試檢查單

> 用途：驗證權限邊界（GitLab 角色、Jenkins 授權、部署審批、合併門檻、雲端 IAM 最小權限、網域/憑證）是否符合設計。
> 用法：照「測試方式」執行，把結果填入「實際行為」，與「預測行為」比對，相符打 ✓。

替換變數：`GL=http://192.168.0.10/api/v4`、專案 id=2、各角色 token 用該帳號自己的 PAT。

---

## A. GitLab 角色與分支保護

| # | 測試項目 | 測試方式（指令/動作） | 預測行為 | 實際行為 | 通過 |
|---|---|---|---|---|---|
| A1 | programmer 直推 main | 以 programmer 憑證 `git push origin main`（空 commit 測試） | 被拒：`You are not allowed to push code to protected branches` | `remote rejected ... You are not allowed to push code to protected branches`（pre-receive hook declined） | ✓ |
| A2 | programmer 推 feature branch | 以 programmer 憑證 `git push origin feat/x` | 成功 | `[new branch] sectest/merge-perms` push 成功 | ✓ |
| A3 | programmer 開 MR | `POST $GL/projects/2/merge_requests`（programmer token） | 成功（author=programmer） | MR !10 建立，author=programmer | ✓ |
| A4 | programmer 合併 MR | `PUT $GL/projects/2/merge_requests/<iid>/merge`（programmer token） | 被拒（無權限合併） | **HTTP 401 Unauthorized**（GitLab 對無權合併回 401；Developer 不能 merge） | ✓ |
| A5 | devops 合併 main | 同上（devops token；註：develop 帳號已於角色整併移除） | 被拒（Developer） | **HTTP 401 Unauthorized** | ✓ |
| A6 | PM 合併（pipeline 綠） | `PUT .../merge`（pm token，pipeline=success） | 成功 merged | **HTTP 200** state=merged by=pm | ✓ |
| A7 | PM 合併（pipeline 未過） | `PUT .../merge`（pm token，pipeline≠success） | 被拒（合併門檻擋） | **HTTP 405 Method Not Allowed**（PM 有權限，但 pipeline 門檻擋） | ✓ |
| A8 | 開放註冊 | 瀏覽 `http://192.168.0.10/users/sign_up` | 302 轉走（註冊已關閉） |  |  |

## B. Jenkins 授權（Matrix）

| # | 測試項目 | 測試方式 | 預測行為 | 實際行為 | 通過 |
|---|---|---|---|---|---|
| B1 | 匿名看 build | `curl -s -o /dev/null -w "%{http_code}" https://jenkins.buy0050.xyz/job/tibame_project/job/main/lastBuild/` | 403 |  |  |
| B2 | 匿名存取 OIDC discovery | `curl ... https://jenkins.buy0050.xyz/oidc/.well-known/openid-configuration` | 200（CI 聯合驗證需要，須保持公開） |  |  |
| B3 | devops 看 build | `curl -u devops:*** .../lastBuild/` | 200 |  |  |
| B4 | devops 進管理頁 | `curl -u devops:*** https://jenkins.buy0050.xyz/manage/` | 403 |  |  |
| B5 | devops 用 script console | `curl -u devops:*** .../script` | 403 |  |  |
| B6 | admin 完整權限 | `curl -u admin:*** .../manage/` | 200 |  |  |

## C. 部署審批與 CI 門檻

| # | 測試項目 | 測試方式 | 預測行為 | 實際行為 | 通過 |
|---|---|---|---|---|---|
| C1 | MR 只測容器 | 開 MR → 看 MR-N build 的 stage | Checkout/Build/Test 跑，Push/Deploy `skipped` |  |  |
| C2 | MR 測試失敗擋 merge | 故意讓 Test 失敗 → 看 GitLab MR | head_pipeline=failed、merge 被擋 |  |  |
| C3 | MR 通過才通知 | MR 測試通過 → 看 Discord | 測試後才出現「📬 PR 已開啟」 |  |  |
| C4 | main 不自動部署 | merge 進 main → 看 main build | 停在 `Deploy / Abort`（input） |  |  |
| C5 | devops 核准部署 | 以 devops 按 Deploy（或 API proceed） | 成功，繼續部署 |  |  |
| C6 | 非 devops 核准 | 以其他帳號嘗試 proceed input | 被拒（submitter 限定 devops/admin） |  |  |

## D. 雲端 IAM 最小權限（GCP）

> 測法：用 owner 以 `--impersonate-service-account=jenkins-deploy@ckc101-13.iam.gserviceaccount.com` 模擬該 SA 實際能不能做。

| # | 測試項目 | 測試方式 | 預測行為 | 實際行為 | 通過 |
|---|---|---|---|---|---|
| D1 | 該推 image（允許） | `gcloud artifacts docker images list asia-east1-docker.pkg.dev/ckc101-13/myfirstweb --impersonate-service-account=jenkins-deploy@...` | 成功（有 artifactregistry.writer） |  |  |
| D2 | 列 VM（禁止） | `gcloud compute instances list --impersonate-service-account=jenkins-deploy@...` | 權限不足（只有 loadBalancerAdmin） |  |  |
| D3 | 存取股票 bucket（允許） | `gcloud storage ls gs://ckc101-13-stock-data --impersonate-service-account=jenkins-deploy@...` | 成功（objectAdmin 限此 bucket） |  |  |
| D4 | 存取其他 bucket（禁止） | `gcloud storage ls gs://ckc101-13-bucket-name-12345 --impersonate-service-account=jenkins-deploy@...` | 權限不足 |  |  |
| D5 | 建 service account（禁止） | `gcloud iam service-accounts create test-x --impersonate-service-account=jenkins-deploy@...` | 權限不足 |  |  |

## E. 雲端 IAM 最小權限（AWS）

> 測法：jenkins-deploy 信任只允許 OIDC（不能 IAM `assume-role`），故用 **IAM Policy Simulator**（owner 權限）評估該 role 政策：
> `aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::112064333943:role/jenkins-deploy --action-names <動作> [--resource-arns <資源>]`
> 回 `allowed` / `implicitDeny` / `explicitDeny`。

| # | 測試項目 | 測試方式（動作 / 資源） | 預測行為 | 實際行為 | 通過 |
|---|---|---|---|---|---|
| E1 | 該推 ECR（允許） | `ecr:DescribeRepositories` | allowed | **allowed** | ✓ |
| E2 | 列 IAM（預期已拒） | `iam:ListRoles` | explicitDeny | ① 修復前 allowed（`AmazonECS_FullAccess` 給的；紅隊真打列出 role 名）→ ② 加 `Deny iam:List*/Get* on *` → recon 擋了，但**部署 #30 失敗**：terraform refresh `ecsTaskExecutionRole` 需要 `iam:GetRole`，被一起擋掉 → ③ 改成 **scoped Allow（只讀 ecsTaskExecutionRole）+ Deny（帳號級列舉 ListRoles 等）** → `iam:ListRoles`=explicitDeny、`iam:GetRole@ecsTaskExecutionRole`=allowed、**真部署 #31 SUCCESS**。教訓：**Deny 不能用 `iam:Get*/List* on *`，且 simulator 過 ≠ 真部署過，要跑真部署驗證** | ✓ |
| E3 | 存取 state bucket（允許） | `s3:ListBucket` @ `ckc101-13-bucket-name-12345` | allowed | **allowed** | ✓ |
| E4 | 存取其他 S3（禁止） | `s3:ListBucket` @ 任意其他 bucket | implicitDeny | **implicitDeny** | ✓ |
| E5 | 建 IAM user（禁止） | `iam:CreateUser` | implicitDeny | **implicitDeny** | ✓ |

> **E2 發現**：移除 inline 後，`iam:GetRole/GetRolePolicy/ListRolePolicies/GetOpenIDConnectProvider/ListOpenIDConnectProviders` 皆已 deny，但 `iam:ListRoles`、`iam:ListAttachedRolePolicies` 仍 allow，來源是 `AmazonECS_FullAccess`。若要完全關閉 IAM 列舉，需加一段 **explicit Deny**（保留 `iam:PassRole`，否則 ECS 部署會壞），或把 ECS_FullAccess 換成自訂的窄政策。

## F. 網域 / 憑證

| # | 測試項目 | 測試方式 | 預測行為 | 實際行為 | 通過 |
|---|---|---|---|---|---|
| F1 | HTTP 轉址 | `curl -s -o /dev/null -w "%{http_code} %{redirect_url}" http://buy0050.xyz` | 301 → https://buy0050.xyz | `301` → `https://buy0050.xyz:443/` | ✓ |
| F2 | HTTPS 正常 | `curl -sI https://buy0050.xyz` | 200，憑證有效（綠鎖） | `200 OK`；憑證 CN=buy0050.xyz、Google Trust Services(WR3) 簽發、有效至 2026-09-19、鏈受信任（未加 -k 也通過） | ✓ |
| F3 | DNS 指向 | `nslookup buy0050.xyz` | A → 34.8.85.156（灰雲 DNS-only） | A → `34.8.85.156` | ✓ |

---

## 測試結果摘要

| 區塊 | 通過 / 總數 | 備註 |
|---|---|---|
| A. GitLab 角色 | **7 / 8** ✓ | A1~A7 實測通過；A8（註冊關閉）待測 |
| B. Jenkins 授權 | / 6 | |
| C. 審批與門檻 | / 6 | |
| D. GCP IAM | / 5 | |
| E. AWS IAM | **5 / 5** ✓ | E2 原本未過（ECS_FullAccess 放行 IAM 列舉），已加 explicit Deny 修復並紅隊真打確認 |
| F. 網域憑證 | **3 / 3** ✓ | 2026-06-22 實測通過 |

測試日期：________　測試人：________
