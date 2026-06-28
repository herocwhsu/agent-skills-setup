# Backlog

Ideas deferred until a dependency ships or a project milestone is reached.

---

## FIRST DIGITAL — 6 個月執行計畫（2026-06 起）

> 逆向工作法完整分析已完成，文件位於：
> `~/projects/agent-skills-setup/docs/firstdigital-reverse-engineering.md`

### 核心原則
不做收入模式不確定的功能，只做「建立用戶習慣 + 驗證付費意願」的事。
Phase 2/3（廣告、B2B 授權、Discord 社群、國際化）全部降優先，等 Email 名單驗證後再議。

---

### 第一件事：Email 週報（Month 1–2）✅ 已上線（2026-06-28）

**解決痛點**：被動查詢時機錯誤（痛點 3）

**技術清單**
- [x] PostgreSQL `newsletter_subscribers` 表（migration 007）
- [x] Resend API 串接（`RESEND_API_KEY` in Vault，domain verified）
- [x] 後端 CronJob：每週一 00:00 UTC（台灣 08:00）觸發
- [x] 前端訂閱表單：首頁底部 + Insight 頁側邊欄
- [x] Double opt-in 確認信（英文）
- [x] 每封週報底部一鍵退訂連結
- [x] Playwright E2E 測試（6 tests passing）
- [x] Deploy workflow 修正（image_name 錯誤 → 已修）
- [x] Dark mode 防護（color-scheme: light）

**現況**：等待 Month 2 驗收
**驗收標準**：Email 名單 ≥ 500 人，開信率 ≥ 30% → 才啟動第二件事

---

### 第二件事：市場溫度指數 0–100（Month 2–3）

**解決痛點**：資訊碎片化（痛點 1）+ 解讀鴻溝（痛點 2）

**技術清單**
- [ ] 加權計算邏輯：`temperature = CAPE_percentile × 0.6 + Buffett_percentile × 0.4`
- [ ] 附加至現有 `/indicators/context` Redis 快取（現有 API 已有兩個分位數，加一條計算）
- [ ] 首頁重構：溫度指數大數字 + 四色溫度計（藍 0–40 / 綠 40–60 / 黃 60–80 / 紅 80–100）
- [ ] 一句解讀文字（現有 AI 洞見已有，調整輸出格式）

**驗收標準**：首頁 5 秒內傳遞市場定位感；溫度指數截圖被自然分享到 PTT/Dcard

---

### 第三件事：歷史情境對比（Month 4–6，簡化版）

**解決痛點**：決策孤獨感（痛點 5）

**技術清單**
- [ ] 後端：查詢歷史上 CAPE 值距當前最近的 3 個時間點，計算各自之後 1Y/2Y/5Y 報酬
  - 使用現有 DB：`cape_details` 全史（1,746 筆）+ `price_index`（已有）
  - 不需新數據源
- [ ] 前端：靜態對比卡片（3 張），自動對應當前 CAPE 水位
  - CAPE 35–40 → 對比 2021 年高點
  - CAPE 40+ → 對比 2000 年科技泡沫
  - CAPE 20–25 → 對比 2011 年歐債危機後

**驗收標準**：點擊率 ≥ 15%，分享次數 ≥ 50 次/月（Month 5 後）

---

### 小修：Operator Memo 標籤更名（隨時可做，低工時）

- [ ] `InsightDetailPage.tsx`：標題從 `Operator Memo` 改為 `Historical Context`
- [ ] 在備忘框下方加一行小字免責聲明：「以下內容為教育性參考，非投資建議」
- **原因**：金管會法規風險，「行動建議」框架若被認定為投資顧問服務需取得執照

---

### 付費版啟動條件（Month 6+，等驗證後再執行）

當 Email 名單 ≥ 2,000 人 且 週報開信率 ≥ 35% 時，啟動：
- [ ] Google OAuth 或 Email + 密碼帳號系統
- [ ] `user_alerts` 表（user_id, indicator, threshold, direction, channel）
- [ ] Stripe 金流串接（NT$199–299 / 月，7 天免費試用）
- [ ] 付費版核心功能：個人化 CAPE / 巴菲特閾值警示

---

### 方法論透明頁（隨時可做，SEO 加分）

- [ ] 獨立頁面：數據來源（Yale Shiller、FRED）、計算公式、溫度指數權重說明、歷史回測說明
- **原因**：理工背景用戶（核心受眾）對「黑盒子結論」天然排斥，透明度是信任的前提

---

## After robots replacement ships

**Source:** [Anthropic — Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)

### Evaluator-Optimizer on news classify pipeline

Add a second LLM pass that scores classification confidence and re-runs classify on low-confidence results before storing. Implements the Evaluator-Optimizer workflow pattern from the Anthropic article.

Current pipeline (robots, to be ported to replacement):
```
fetch_news → classify_news → store
```

Target pipeline:
```
fetch_news → classify_news → evaluator (confidence check) → re-classify if low → store
```

**Why deferred:** robots is being replaced by two new projects. Port this pattern when the replacement news pipeline is built, not retrofitted into robots.

**Effort:** ~1 LLM call added to classify step. Low risk, high data quality payoff.

---

### Agent workflow patterns to apply in new projects

From the same article — patterns already in use vs. gaps:

| Pattern | Status |
|---|---|
| Prompt chaining | ✅ Already doing (fetch → classify) |
| Orchestrator-workers | ✅ ai-hedge-fund |
| Parallelization | ✅ ai-hedge-fund investor agents |
| Routing | ❌ Not implemented — route stock queries to different agents based on type |
| Evaluator-Optimizer | ❌ This backlog item |

Routing idea: when robots replacement API receives a query, classify it first (single LLM call), then route to: fundamentals agent / CAPE context / news sentiment DB.
