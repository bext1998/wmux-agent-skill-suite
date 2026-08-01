# wmux-agent-skill-suite 規格書

## 目標

- 提供兩個 coding-agent 中立、以 `SKILL.md` 格式撰寫的技能，涵蓋在 [wmux](https://github.com/amirlehmam/wmux) 多視窗終端機環境下的 pane 操作與跨 pane 派工協調：
  - `skills/wmux-best-practice`：單一 pane 對其他 pane 的基礎操作 primitive（讀畫面、送訊息、建立/清除 pane）。
  - `skills/wmux-coordinator`：建立在 `wmux-best-practice` 之上的 orchestrator 流程（Worker Registry、單行任務協議、派工/輪詢/升級規則、per-harness 適配層）。
- 讓任何支援 `SKILL.md` 或相容技能格式的 coding agent（Claude Code、Codex、OpenCode、Pi 等）都能安裝並使用同一份技能內容，差異只落在安裝路徑與安裝方式。
- 以本 repository 建立時 wmux 官方最新正式版本為基準做適配與驗證，並在版本紀錄中留存 tag／commit SHA／平台／capabilities。
- 獨立於 [maze-coder](https://github.com/bext1998/maze-coder) 維護、測試、發布，不依賴其同步或發布流程。

## 非目標

- 不縮減或重新定位原 `wmux-orchestrator`（現 `wmux-coordinator`）的能力。
- 不將兩個技能拆分到不同 repository，也不允許只安裝其中一個而讓另一個的內部引用失效。
- 不為不同 coding agent 維護多份分叉的技能內容——核心技能只有一份 `SKILL.md` source of truth，per-agent 差異只存在於安裝文件/腳本。
- 不與 maze-coder 建立任何執行期相依（不呼叫其 script、不讀取其設定）。
- 不長期同時維護新舊名稱（`wmux`／`wmux-orchestrator` 舊名稱不在本 repo 內提供）。
- 不保證支援所有過去或未來的 wmux 版本；版本相容性以「版本重新驗證紀錄」段落逐次記錄，非長期承諾。
- 不因實作期間 upstream 發新版本就無限擴張既有任務範圍——除非新版本直接使現有內容失效，否則另開新 Issue 處理。

## 技能責任邊界

| 技能 | 負責 | 不負責 |
|---|---|---|
| `wmux-best-practice` | wmux 靜默環境偵測、四類操作授權分級、`ok:true` 陷阱、`--surface`/`--pane` 定位限制、pane-to-pane 交接流程、pane/分頁建立與清除 | 任何跨 pane 派工協議、Worker Registry、per-harness 忙碌/完成標記判斷 |
| `wmux-coordinator` | Worker Registry（session 內）、單行任務封包協議（`TASK#`/`DONE#`/`FAILED#`/`BLOCKED#`）、派工→核對→提交→輪詢流程、升級規則、per-harness 適配層 | 重新定義或複製 `wmux-best-practice` 已有的授權邊界與 primitive——一律用相對路徑引用，不得另立一份 |

兩者必須同層安裝（例如同時放在 `~/.claude/skills/` 下），讓 `wmux-coordinator` 對 `../wmux-best-practice/SKILL.md` 的相對引用能被 coding agent 正確解析。

## 相容性策略

- **coding agent 中立**：核心技能內容（`skills/*/SKILL.md`）不得使用特定 coding agent 的 plugin API、hook、subagent 機制、模型名稱或固定安裝路徑；只依賴 wmux CLI 本身與一般 shell 能力。
- **wmux 版本**：以建立本 repository 時的 wmux 最新正式版為驗證基準，記錄於各技能檔案內的「版本重新驗證紀錄」段落。版本落差時，技能內文的既有具體結論（旗標是否有效、預設落點等）應視為未驗證，需依技能內「靜默環境偵測」/「版本重新驗證」段落描述的方法重新核對，而不是直接信任舊紀錄。
- **平台**：目前的實測記錄皆基於 Windows（`win32`）。macOS/Linux 尚未實測，行為可能不同；使用前應先以唯讀指令（`identify`/`capabilities`）核對再決定是否套用既有結論。
- **能力探測優先於硬編碼假設**：任何自動化流程在依賴某個 wmux 能力前，應先用 `capabilities`／`identify` 或前置的 `--help` 確認，並在能力不存在或版本不相容時提供安全 fallback（例如退回輪詢文字標記，而非假設新指令一定可用）。

## 安全規則

- 技能內容不得讀取、印出、記錄或以任何形式外洩 `$WMUX_PIPE_TOKEN`、`wmux token` 等驗證憑證。
- 呼叫任何會改變狀態的 wmux 指令前，依技能內「執行前的授權邊界：四類操作」分級（唯讀／可逆寫入／建立資源／破壞性）套用對應的謹慎程度；破壞性操作一律要求精確 ID 核對與使用者/任務明確授權。
- 不透過 `agent spawn` 或其他機制去「附加」或接管一個已經在互動運行的既有 pane。
- 不建立任何跨 session 持久化的狀態檔、daemon 或背景服務；`wmux-coordinator` 的 Worker Registry 只存在於當次 orchestrator session 的工作記憶裡。
- 不呼叫 `hook --event`（觸發使用者自訂 hook，後果不可預期）、不呼叫 `ssh`/`bridge`（跨機器/跨網路操作）——這些不在兩個技能的範圍內。
- 通用安裝腳本（`scripts/install.sh`）只做檔案複製，不下載任何遠端內容、不執行任何來源不明的程式碼。

## 測試方式

本 repository 區分兩種驗證，見 [docs/testing.md](testing.md) 的完整說明：

1. **靜態 CI 驗證**（`.github/workflows/`，於 PR 與 push main 時執行，任何平台皆可跑）：frontmatter 格式、資料夾/技能名稱一致性、必要檔案存在、相對引用有效、無舊名稱或 `maze-*` 前綴殘留、安裝腳本可裝進臨時目錄。
2. **Windows wmux 實機驗證**（本機手動執行，CI 不跑）：實際在 Windows 上執行 `wmux identify`/`capabilities` 及技能內描述的指令流程，確認行為與文件描述一致。技能文件內的「版本重新驗證紀錄」只在完成這類實機驗證後才能更新。

## 發布流程

- 版本號遵循語意化版本；首次發布為 `v0.0.1`。
- 發布前需完成：CHANGELOG 更新、CI 全綠、README/安裝文件與實際檔案結構一致。
- Git tag 與 GitHub Release 由維護者在完成人工複審後建立，不在一般 PR 合併流程中自動觸發。
- Release notes 需列出：技能來源（遷移自 maze-coder 的 commit/PR）、重新命名對照、wmux 驗證版本與 tag/commit SHA、安裝方式、已知限制。
