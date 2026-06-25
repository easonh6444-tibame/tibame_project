# tibame_project 介紹網站（Cloudflare Pages）

介紹整個專案的靜態網站，右下角有懸浮 AI 助理（Gemini），可詢問專案細節。

## 結構

```
website/
├─ index.html              # 單頁網站（各部分介紹 + 嵌入流程圖）
├─ style.css               # 樣式（含聊天氣泡）
├─ app.js                  # 前端：技術棧圖示 + AI 聊天邏輯
├─ assets/
│  ├─ diagram.svg          # CI/CD 流程圖（向量，網頁顯示用）
│  └─ diagram.png          # 流程圖點陣備份
└─ functions/
   └─ api/
      └─ chat.js           # Cloudflare Pages Function：呼叫 Gemini 的聊天後端
```

> AI 聊天為什麼需要後端？因為 Gemini API key 不能放在前端（會外洩）。Cloudflare Pages 的
> **Pages Functions**（serverless）就是這個「server」：`/api/chat` 由 `functions/api/chat.js`
> 處理，在伺服器端帶上 key 呼叫 Gemini。（這比「MCP server」更適合網頁聊天 —— MCP 是給 AI
> 客戶端/工具用的協定，不是給網頁直接呼叫的後端。）

## 部署到 Cloudflare Pages

1. 把 **`website/` 這個資料夾**當作 Pages 專案根目錄（用 Git 連動或 `wrangler` 直接上傳）。
   - 建置設定：Framework 選 None；Build command 留空；**Build output directory 設為 `/`（網站根）**。
2. 設定環境變數（Settings → Environment variables，建議設成 **Secret**）：
   - `GEMINI_API_KEY` = 你的 Gemini API key
3. 部署。`functions/api/chat.js` 會自動成為 `/api/chat` 端點。

### 用 Wrangler 部署（CLI）

```bash
npm i -g wrangler
cd website
# 本地預覽（含 Functions）：把 key 放進 .dev.vars
echo 'GEMINI_API_KEY=你的key' > .dev.vars
wrangler pages dev .

# 直接部署
wrangler pages deploy . --project-name tibame-project-site
# 設定正式環境的 key：
wrangler pages secret put GEMINI_API_KEY --project-name tibame-project-site
```

## 本地快速預覽（不含 AI）

只看版面：用任意靜態伺服器開 `website/`，例如：

```bash
cd website && python -m http.server 8000   # 或 npx serve .
```

（純靜態預覽時 `/api/chat` 不會運作，AI 聊天需要 `wrangler pages dev` 或實際部署。）

## 更新流程圖

流程圖來源是 `diagram.drawio`（專案根目錄）。修改後重新匯出 `assets/diagram.svg` / `.png`
覆蓋即可（用 draw.io 匯出，或本專案使用的 next-ai-drawio MCP）。

## 備註

- 這是第一版（prototype），之後可再調整版面、內容與 AI 行為。
- AI 的專案知識寫在 `functions/api/chat.js` 的 `SYSTEM_PROMPT`；要更新介紹內容改那裡即可。
