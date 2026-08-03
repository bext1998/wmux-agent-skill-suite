# Changelog

本專案遵循[語意化版本](https://semver.org/lang/zh-TW/)。版本號進位規則另見 [docs/SPEC.md](docs/SPEC.md#發布流程)：`0.0.x` 階段一律只進位第三位數字，直到第三位數達到雙位數才改用一般語意化版本規則（依變更規模決定進哪一位）。

## [Unreleased]

### Added

- 追蹤 upstream wmux `v0.42.0`（2026-08-03 發布，[release notes](https://github.com/amirlehmam/wmux/releases/tag/v0.42.0)）的已知資訊（issue #8）：該版本修好了造成本專案放棄 `v0.41.0`、改採 `v0.38.0` 的兩個嚴重效能問題（diff pane 輪詢失控狂噴 `git.exe`、crash 後 process 樹殘留），以及 `wmux tree --workspace`／`list-surfaces --workspace`/`--pane` 旗標修復、V2 指令全面攜帶 `WMUX_SURFACE_ID` 這兩項 CLI 表面異動。內容全部來自比對官方 release notes 與對應 commit，**未進行 Windows wmux 實機驗證**，因此本次不變更「版本重新驗證紀錄」或版本基準（維持 `v0.38.0`），也不宣稱已對 `v0.42.0` 完成適配。詳見兩個技能檔案內新增的「v0.42.0 已知資訊」段落與 [README.md](README.md#版本基準)。後續若要正式將驗證基準升級到 `v0.42.0`，需要另外完成 `docs/testing.md` 第 2 節描述的實機驗證流程。

## [0.0.1] - 2026-08-02

### Added

- 初始化 repository 結構：`skills/`、`docs/`、`scripts/`、`tests/`、`.github/workflows/`。
- 新增 `skills/wmux-best-practice`：遷移自 [maze-coder](https://github.com/bext1998/maze-coder) `extensions/wmux`（`wmux` 技能），僅更新 frontmatter、標題、描述與路徑引用，未縮減任何觸發情境、操作能力或安全邊界。
- 新增 `skills/wmux-coordinator`：遷移自 maze-coder `extensions/wmux-orchestrator`（`wmux-orchestrator` 技能），僅更新 frontmatter、標題、描述與對 `wmux-best-practice` 的相對路徑引用，未縮減 Worker Registry、狀態模型、失敗/blocked 升級規則或 per-harness 適配層。
- 以 wmux `v0.38.0`（annotated tag SHA `60dd5e51e1ccf269b3d59290f33b985a79763837`，commit `7882751c57da360635d22c36ff13f6294af27796`，platform `win32`，capabilities `protocols: ["v1","v2"]` / `features: ["workspaces","splits","notifications"]`）重新核對兩個技能的既有結論，`identify`/`capabilities`/CLI 指令列表/自身 surface 的 `read-screen` 已實際重跑確認；破壞性/建立資源類指令與跨 pane 派工流程沿用既有 0.36.0 記錄，本次未重新互動驗證。
- 最初曾以 `v0.41.0`（tag SHA `60127c5d37ec9d24ae6640cac1f5793a20e76ac6`，commit `390aa5beef1c9dfc07ebe02db3db3c8229462260`）作為適配基準；使用者實際使用後回報該版本有嚴重效能問題，因此改採 `v0.38.0`。v0.41.0 只作為已知限制與暫不採用原因保留紀錄，不作為驗證基準；其 CLI 說明中新增的 `report-agent`/`answer-agent`/`report-metadata`/`report-session`/`release-agent`/`agent-state` 指令家族經核對在 `v0.38.0` 上不存在，故不採用、不記錄為可用能力。
- 新增 `docs/SPEC.md`、`docs/skill-authoring-rules.md`、`docs/testing.md`、`docs/install.md`、`docs/migration.md`、`AGENTS.md`、`CLAUDE.md`。
- 新增通用安裝腳本 `scripts/install.sh`，可安裝兩個技能到任意目標技能目錄。
- 新增 `tests/` 下的靜態驗證腳本與 `.github/workflows/ci.yml`，於 PR 與 push `main` 時執行。
- 改用真正合規的 YAML parser（`js-yaml`，見 `package.json`/`package-lock.json`）解析 frontmatter，取代先前只 grep 字串的作法；新增多項負向測試（malformed YAML、duplicate key、frontmatter 非 mapping、`name` 欄位含換行注入、block scalar 內縮排的 `---` 誤判、timestamp scalar 誤判成 mapping 等），CI 改用 `actions/setup-node@v4`（Node 24）+ `npm ci`。
- 強化 `scripts/install.sh` 的路徑安全檢查：解析 `skills/` 本身的 symlink 真實路徑、正規化 Windows 原生 drive-letter 路徑並拒絕 bare drive root、NTFS 大小寫不敏感比對、`realpath -m` capability probe（拒絕不支援的 BSD/macOS realpath 並給出明確訊息）、明確拒絕 Windows drive-relative 路徑（如 `C:foo`）、mkdir／第二次 `cd` 一律使用已驗證過的絕對路徑並加 `--` 避免觸發 Bash `cd -` 特例（修正 target 為單一 `-` 時的路徑錯亂/半成品安裝問題）。對應新增十餘項負向測試情境，涵蓋 MSYS 專屬情境與反向的「非 MSYS 不誤傷」情境。
- 重新確認 upstream 於 v0.38.0 之後（v0.39.0–v0.41.0）的官方 Release Notes 差異範圍：新增的 agent-state／`answer-agent` 家族僅存在於 v0.41.0，且 upstream 文件明確聲明 Claude Code 尚無法宣告 `--choices`；核心 pane 操作 primitive（`send`/`send-key`/`read-screen`/`tree`/`list-panes`/`split`/`close-pane`/`agent spawn`）在四份 Release Notes 中均未被提及有行為變更。詳見兩個技能檔案內對應的「v0.0.1 發布前差異調查／補充」段落。

### Notes

- 本版本為初次發布；`v0.0.1` git tag / GitHub Release 由維護者在完成人工複審後手動建立，見 [docs/SPEC.md](docs/SPEC.md#發布流程)。
