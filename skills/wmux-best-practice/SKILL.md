---
name: wmux-best-practice
description: 在 wmux（多視窗終端機）環境下操作其他 pane、跟另一個在互動運行的 agent 交接，或建立/清除 pane 與分頁時使用。使用者說「轉交給 codex/claude 那個 pane」「跟另一個 pane 說一聲」「切一個新的 pane」等語句、或畫面上出現多個 wmux pane 時觸發。不涵蓋 `browser`／`markdown` 兩類指令——不在本技能範圍內。
---

# wmux-best-practice

## 目標

在 wmux 多視窗終端機環境下，安全、正確地操作其他 pane：讀取其他 pane 的畫面內容、把文字送進另一個正在互動運行的 agent pane（例如向另一個 coding CLI 交接審查或任務）、或視需要建立/清除 pane 與分頁——同時避開已經實際驗證過的幾個陷阱。

## 靜默環境偵測（進入任何 wmux 操作前）

在呼叫本技能的任何指令之前，先靜默判斷自己是否真的身處 wmux 環境——不要假設呼叫者已經口頭告知。整個偵測過程只判斷「存在與否」，不解讀、不輸出任何憑證內容。

1. **先查 env 變數，只判斷存在，不讀值**：檢查 `$WMUX`、`$WMUX_SURFACE_ID` 是否存在（PowerShell：`$env:WMUX`、`$env:WMUX_SURFACE_ID`；POSIX shell：`$WMUX`、`$WMUX_SURFACE_ID`）。兩者都存在 → 判定身處 wmux，`$WMUX_SURFACE_ID` 即為自己的 surface id，可省略後續定位查詢。**絕對不要讀取、印出、記錄或以任何形式外洩 `$WMUX_PIPE_TOKEN` 的值**——這組變數等同技能中已禁用的 `token` 指令輸出，偵測時只允許檢查它是否存在（例如用來判斷「這個 shell 有沒有繼承完整 wmux env」），不得用在別的地方。
2. **env 不足時的唯讀 fallback**：`$WMUX`／`$WMUX_SURFACE_ID` 缺一或全無時，改呼叫唯讀指令 `wmux identify`（或 `wmux ping`）。成功回應 → 判定身處 wmux（例如巢狀 shell 未繼承 env 的情況），但沒有 `WMUX_SURFACE_ID` 可用時，需另外用 `tree`／`list-panes` 找出自己的 surface id 才能繼續。失敗（非零 exit code 或錯誤）→ 判定不在 wmux 環境下。
3. **env 可能過期時二次確認**：`$WMUX=1` 只代表這個 process 曾經繼承到該變數，不保證底層 pipe 目前仍存活。在依賴 env 判斷結果去執行任何非唯讀指令（可逆寫入／建立資源／破壞性操作）之前，先用 `identify` 或 `ping` 二次確認 pipe 仍然可用；只做唯讀查詢（如 `read-screen`）時可以省略這一步。
4. **非 wmux 環境安靜退出**：判定不在 wmux 底下時，直接安靜跳過本技能其餘所有內容，不觸發、不嘗試任何其他 wmux 指令，也不需要向使用者報告「偵測失敗」這件事本身——除非使用者本來就是在問「這是不是 wmux 環境」。
5. **版本漂移仍需重新驗證**：`identify`/`ping` 確認完「身處 wmux」只代表偵測本身成功，不代表下面「驗證環境與適用範圍」列出的具體行為結論依然成立——版本不符時一律視同未驗證，套用下一節的重新確認方法。逐版驗證歷史見 [CHANGELOG.md](../../CHANGELOG.md)。

## 驗證環境與適用範圍

以下具體行為結論的目前驗證基準：`wmux v0.42.0`（`platform: win32`；capabilities `protocols: ["v1","v2"]`、`features: ["workspaces","splits","notifications"]`）。**這些是特定版本下實測觀察到的行為，不是保證不變的 API 契約。** 換到不同版本、平台或回報不同 capabilities 的 wmux instance 前，先用 `identify`／`capabilities` 核對，版本不同就視同未驗證，用「靜默環境偵測」的方法重新確認，不要直接套用下面的具體結論。各版本的驗證方式、觀察紀錄與差異調查見 [CHANGELOG.md](../../CHANGELOG.md)，本文件只保留目前仍然成立的結論。

## 執行前的授權邊界：四類操作

呼叫任何 wmux 指令前，先判斷它屬於哪一類，套用對應的謹慎程度。這四類跟後面「定位是否可靠」是不同維度，兩者都要顧到：

**唯讀（可自由呼叫，沒有副作用）**：`identify`、`capabilities`、`ping`、`tree`、`list-panes`、`list-surfaces`、`list-windows`、`list-workspaces`、`list-notifications`、`read-screen`、`config show`／`config path`。

**可逆寫入（會改變某個既有 pane 的內容或產生可見狀態，但不會憑空消滅資源）**：`send`、`send-key`、`notify`。**目標 pane 與寫入內容都必須是使用者明確要求、或當下任務直接需要的**，不要自己延伸去操作使用者沒提到的 pane。`notify` 會產生使用者看得到的通知——這是真實、外顯的狀態變更，不是無害的背景查詢，呼叫前一樣要確認是使用者要的動作。

**建立資源（會新增 pane、分頁或 process，佔用畫面與系統資源）**：`split`、`new-surface`、`agent spawn`。只在有明確任務需求時才呼叫（例如使用者要求開新工作區、或需要背景執行一個獨立任務），不要為了「探索指令行為」就隨意建立。

**破壞性（會關閉或終止既有東西，且無法復原內容）**：`pane close`（verb form）、`close-surface`、`agent kill`。**執行前必須確認：(a) 目標 ID 精確無誤——用 `tree`／`list-panes`／`agent list` 核對，不要憑記憶或猜測；(b) 這是使用者明確授權、或當下任務必要的動作。** 即使是「建立資源」類指令意外落在非預期的 pane 上，也不能自行判斷「這應該是空的、關掉沒差」就逕自呼叫破壞性指令清理——那個位置在你查證清楚之前，都可能已經有使用者原本的工作內容，落錯位置本身不構成關閉授權。正確做法：立刻用唯讀指令查清楚實際落在哪裡、目前內容是什麼，回報給使用者，取得明確授權後才清理，不要自作主張。

## 核心原則：`ok: true` 不代表指令真的做到了

這是整份技能最重要的一條通用警語。實測發現多個 wmux 指令會不管三七二十一回傳 `{"ok": true}`，但實際上什麼都沒做，或做在錯的目標上（`close-pane --surface`、`clear-notifications`、`split`／`new-surface --pane` 皆屬此類，具體案例見下方「定位 pane／surface」表格與各操作小節）。

**任何會改變狀態的呼叫，呼叫後都要用對應的唯讀指令（`read-screen`、`list-panes`、`tree`、`list-notifications`）重新查一次，確認真的發生了你以為發生的事，不要只看 `ok: true` 就當作成功。**

## 定位 pane／surface：`--surface`/`--pane` 不是通用旗標

這是第二重要的發現。`--surface`／`--pane` 這組看起來像是「泛用定位旗標」的參數，**只對少數指令真的有效**：`send`、`send-key`、`read-screen`、`agent spawn --pane`。除此之外的指令，即使接受這個旗標也可能靜默忽略：

| 指令 | `--surface`/`--pane` 是否有效 | 正確定位方式 |
|---|---|---|
| `send`、`send-key`、`read-screen` | ✅ 有效，可靠 | 直接用 `--surface <id>` |
| `agent spawn --pane` | ✅ 有效，可靠 | 直接用 `--pane <id>`，`agent list` 核對 `paneId` |
| `close-pane` | ❌ 無效（靜默忽略，`ok: true` 但沒關到） | 改用 verb form：`pane close <paneId>` |
| `close-surface` | 不適用（本來就吃位置參數） | `close-surface <surfaceId>` |
| `clear-notifications` | ❌ 無效 | 改用位置參數：`clear-notifications <notificationId>` |
| `split`、`new-surface --pane` | ❌ 無效，固定作用在（作用中 workspace 的）tree 裡第一個 leaf pane | 沒有已知的可靠定位方式；呼叫前後務必 `tree`/`list-panes` 核對，不要假設它會建在你想要的地方 |
| `zoom-pane` | 純渲染層 toggle，API 查不到效果 | 不建議用於自動化 |
| `focus-surface`／`focus-pane` | 效果無法驗證 | 不要依賴這兩個指令去改變任何後續指令的目標 |

**`send`／`send-key` 沒帶 `--surface` 時，會打到目前真正持有 OS 鍵盤焦點的 pane，不是任何邏輯上「選定」的 pane。** `--surface` 定位不需要目標 pane 曾經被使用者手動點過或呼叫過 `focus-surface`——對完全沒互動過的 pane 一樣可靠。

## 向另一個互動 agent pane 送出訊息（pane-to-pane 交接）

這是把文字可靠送進另一個正在互動運行的 CLI（例如另一個 Claude Code 或 Codex session）的完整流程：

1. `tree` 或 `list-panes` 找出目標 pane 的 `customTitle` 對應的 `surfaceId`。
2. `read-screen --surface <id> --lines 30` 確認目前畫面狀態（例如對方是否正忙碌中）。
3. `send --surface <id> "<訊息內容>"`——單行文字，避免內嵌換行（多行輸入在互動式 TUI 裡的行為未經驗證，換行可能被解讀成送出）。
4. **按 Enter 提交前務必再 `read-screen` 一次，確認待送文字正確出現在目標 pane 的輸入框裡，而不是打到別的 pane。** 這一步不可省略——本技能撰寫過程中就發生過文字誤打進呼叫者自己輸入框的真實案例。
5. 確認無誤後 `send-key enter --surface <id>` 提交。**注意旗標順序：`--surface` 要放在鍵名之後，`send-key --surface <id> enter` 會把 `--surface` 誤判成不合法的鍵名而報錯。**
6. 需要等待對方回覆時，重新 `read-screen` 輪詢；讀到 `{"text": "", "lines": 0}` 不要立刻當作對方畫面真的空白——先重讀一次，原因未明的間歇性空讀確實會發生。

## 建立／清除 pane 或分頁

- `split`／`new-surface` 目前實測固定建立在 tree 裡第一個 leaf pane 上，**沒有已知方法可以指定建在哪裡**。呼叫前先記錄 `tree`／`list-panes` 當基準，呼叫後立刻再查一次，確認新東西實際長在哪裡。**如果蓋到非預期的 pane，不要自行判斷「應該沒差」就逕自關閉**——見上面「執行前的授權邊界」對破壞性操作的要求：先查清楚落點與內容，回報給使用者，取得授權後才清理。
- 關閉：pane 用 `pane close <paneId>`（verb form，可靠）；分頁用 `close-surface <surfaceId>`（可靠）。**不要用 `close-pane --surface <id>`**，實測無效。這兩個指令都屬於破壞性操作，執行前一律套用上面的授權邊界。
- `zoom-pane` 不建議用於自動化流程——純視覺 toggle，無法驗證效果。
- `set-color-scheme`／`list-themes` 純粹是人類使用者的終端機外觀偏好，跟 agent 工作流程無關，不需要使用。

## Agent 指令家族（`agent spawn/status/list/kill`）：不是拿來跟既有 pane 對話的

`agent` 這組指令是用來啟動一個全新的、wmux 自己追蹤管理的 process（`spawn` 一定要帶 `--cmd`），**不能**用來「附加」或「登記」一個已經在互動運行的 pane——對一個既有的手動開啟的 pane 呼叫 `agent status <paneId>` 會回報 `Agent not found`。

- 如果目標是「跟一個已經在跑的互動式 agent session 交接訊息」（例如上面的 pane-to-pane 交接情境），**不要用 `agent` 這組指令**，用 `send`/`read-screen`。
- `agent spawn` 適合的情境是「啟動一個全新的背景任務」，不是溝通機制。不帶 `--pane` 時落點問題跟 `split`/`new-surface` 一樣（見上）；帶 `--pane <id>` 則可靠指定落在哪個既有 pane（`agent list` 的 `paneId` 核對），這點跟 `split`/`new-surface --pane` 不同。落錯地方不代表可以自行清理，一樣要先查清楚、取得授權。
- `agent kill <agentId>` 實測可靠，會讓 `status` 變成 `exited` 並確實終止底層 process。
- `agent list` 是歷史紀錄，已結束的 agent 不會因為 process 死掉或 surface 被關閉就消失——判斷是否還活著要看每筆記錄的 `status` 欄位，不是看它出不出現在清單裡。

## 提醒人類 vs 跟另一個 agent 交換內容

`notify "<文字>"` 是「提醒人類去注意某個 pane」的機制，跟上面的 pane-to-pane `send` 交接是兩件事，可以搭配使用（先 `notify` 提醒、有需要再 `send` 實際內容）：

- `notify` 會自動掛在**呼叫者自己**的 surface 上（不像 `split`/`agent spawn` 那樣落到不確定的預設 pane），定位本身沒有問題；但它會產生使用者看得到的通知，屬於上面「可逆寫入」類的可見狀態變更，呼叫前一樣要確認是使用者要的動作，不是毫無代價的查詢。成功時回應是純文字 `Notification sent`，不是 `{"ok": true}`。
- 有些通知是 wmux 系統自動產生的（例如背景指令執行完畢），不是只有手動 `notify` 才會有。
- `clear-notifications` 記得用位置參數帶通知 id（`clear-notifications <notificationId>`），`--surface` 對這個指令無效。
- `set-status`／`set-progress`／`log` 這組「Sidebar」指令的實際效果無法驗證——呼叫後 `read-screen` 看不到任何變化，推測是寫入畫面上另一塊 UI 區域，但沒有截圖能力可以確認。**不要把任何流程設計成依賴這三個指令的效果**，需要讓人類看到狀態時優先用 `notify`。

## 環境探測

進入 wmux 環境後，可以先呼叫這兩個唯讀指令確認自己身處的環境：

- `identify`：回傳 `{"name": "wmux", "version": ..., "platform": ...}`，確認自己確實在 wmux 底下執行。
- `capabilities`：回傳支援的 protocols／features，可用來事先判斷這個 wmux instance 是否支援你打算用的功能。
- `ping`（回傳 `pong`）、`list-windows`、`list-workspaces` 是簡單的健康檢查/查詢指令，不需要深入。

## 不建議使用／超出範圍

以下指令存在，但跟「pane 間定位/溝通」這個技能的目標無關，或風險/機密性考量超出範圍，**不建議 agent 主動呼叫**：

- `focus-window`／`new-window`：人類手動管理 OS 視窗的操作。
- `new-workspace`／`close-workspace`／`select-workspace`／`rename-workspace`：workspace 生命週期管理，`close-workspace` 可能關掉使用者目前所有工作。
- `ssh`／`bridge`／`token`：跨機器/跨網路操作 wmux 的進階功能；`token` 會印出這個 wmux instance 的有效驗證憑證，不要呼叫或把輸出貼到任何地方。
- `hook --event`：手動觸發使用者自訂的 hook，後果依使用者的設定而定、無法預期。
- `trigger-flash`：用途是推測（可能是吸引人類注意力的視覺提示），未經螢幕視覺驗證，不建議寫進關鍵流程。

## 邊界

- 呼叫前依「執行前的授權邊界」分類；破壞性操作一律需要精確 ID 核對與使用者授權。
- 建立/移除 pane、分頁、agent process 前後一律用唯讀指令核對實際狀態（見「`ok: true` 不代表指令真的做到了」）。
- 不用 `agent spawn` 附加、控制既有互動中的 pane（見「Agent 指令家族」）。
- 不呼叫 `token`、不執行 `hook --event`、不呼叫 `ssh`/`bridge`（見「不建議使用／超出範圍」）。
- 對其他 pane 送出文字前後都要 `read-screen` 核對（見「向另一個互動 agent pane 送出訊息」的完整流程）。
- `report-agent`/`answer-agent`/`report-metadata`/`report-session`/`release-agent`/`agent-state` 這組指令不採用（見 [CHANGELOG.md](../../CHANGELOG.md)）。
