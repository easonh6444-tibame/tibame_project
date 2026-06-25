// Cloudflare Pages Function — AI 聊天後端（呼叫 Gemini）
// 路由：POST /api/chat   body: { message: string, history: [{role, text}] }
// 需要環境變數（Cloudflare Pages → Settings → Environment variables / Secrets）：GEMINI_API_KEY

const MODEL = 'gemini-2.5-flash-lite';

const SYSTEM_PROMPT = `你是「tibame_project」這個專案網站的 AI 助理。請用繁體中文、友善且精簡地回答訪客關於本專案的問題；若問題與本專案無關，禮貌說明你只負責介紹這個專案。

【專案概述】
這是一個台股 0050 ETF 即時儀表板，搭配一條從「推程式碼」到「多雲部署」的全自動 CI/CD 流水線。
線上成品（部署好的 0050 儀表板）網址：https://buy0050.xyz

【應用程式】
- 後端：Python Flask；資料來源 Yahoo Finance（0050.TW），每 10 秒更新。
- 提供 /api/data（現價、開盤、最高/最低、成交量）、/api/history（今日分鐘級走勢）。
- 前端用 Chart.js：折線圖每段依「該點價格 vs 今日開盤」上色（高於=紅漲、低於=綠跌、持平=黑）；x 軸固定當日 09:00–13:30，只顯示當天、跨日重置；另有前十大成份股圓餅圖。
- 容器化（Docker），健康檢查端點 /api/status（埠 19191）。

【CI/CD 流程】
- 原始碼在自架 GitLab；CI 由自架 Jenkins（multibranch pipeline）執行。
- 自動觸發：GitLab webhook (/gitlab-webhook/post) + 每 2 分鐘定期掃描。
- MR pipeline：Checkout → Build（docker build）→ Test（啟動容器 curl 健康檢查）→ 通過後進入 AI Review 階段；測試失敗則靜默不通知。
- main pipeline：Build → Test → Push（推映像到私有 registry）→ Deploy gate（需 devops 核准）→ 部署。整條用單一可編輯的 Discord 進度訊息追蹤。

【AI 程式碼審查】
- 用 Flue 框架驅動 Gemini 模型，讀取 MR 的 git diff，自動產生 100 字內的繁中審查摘要。
- 摘要在測試通過後立即貼到 GitLab MR 留言，供 PM 參考。

【角色分工（各自獨立 GitLab 帳號）】
- programmer：開發、推分支、開 MR。
- pm：審核 AI 摘要並合併到 main。
- devops：核准雲端部署。

【多雲部署】
- 用 Terraform（IaC，state 存於 AWS S3 backend）一次部署到三朵雲：
  - AWS：映像推 ECR，由 ECS 服務運行；以 OIDC 取得臨時憑證（無長期金鑰）。
  - GCP：推 Artifact Registry，部署到 Cloud Run；以 Workload Identity Federation 認證。
  - Cloudflare：Terraform 管理 DNS，並作為靜態網站托管。
- dev 分支則部署到內部測試機取代雲端（不對外公開內部 IP）。

【技術棧】
Flask/Python、Docker、Jenkins、GitLab、Terraform、AWS（ECS/ECR）、GCP（Cloud Run/Artifact Registry）、Cloudflare、Gemini、Flue、Discord。`;

export async function onRequestPost(context) {
  const { request, env } = context;

  const key = env.GEMINI_API_KEY;
  if (!key) {
    return json({ error: '伺服器尚未設定 GEMINI_API_KEY。' }, 500);
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: '請求格式錯誤。' }, 400);
  }

  const message = (payload && typeof payload.message === 'string') ? payload.message.trim() : '';
  if (!message) return json({ error: '訊息不可為空。' }, 400);

  const history = Array.isArray(payload.history) ? payload.history : [];
  const contents = [];
  for (const h of history.slice(-12)) {
    if (h && (h.role === 'user' || h.role === 'model') && typeof h.text === 'string') {
      contents.push({ role: h.role, parts: [{ text: h.text }] });
    }
  }
  contents.push({ role: 'user', parts: [{ text: message }] });

  const body = {
    system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents,
    generationConfig: { maxOutputTokens: 800, temperature: 0.6, thinkingConfig: { thinkingBudget: 0 } },
  };

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${key}`;
  const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

  try {
    let r, detail = '';
    // 遇 503（忙線）或 429（限流）自動重試，最多 4 次、退避遞增。
    for (let attempt = 0; attempt < 4; attempt++) {
      r = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (r.ok) break;
      detail = await r.text();
      if ((r.status === 503 || r.status === 429) && attempt < 3) {
        await sleep(600 * (attempt + 1));
        continue;
      }
      break;
    }
    if (!r.ok) {
      return json({ error: 'AI 目前忙線中，請過幾秒再問一次。', detail: detail.slice(0, 200) }, 503);
    }
    const data = await r.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    return json({ text: text || '抱歉，我沒有產生回覆，請換個方式再問一次。' });
  } catch (err) {
    return json({ error: '呼叫 AI 時發生錯誤。' }, 500);
  }
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}
