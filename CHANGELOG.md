# Changelog

本專案遵循[語意化版本](https://semver.org/lang/zh-TW/)。

## [Unreleased]

### Added

- 初始化 repository 結構：`skills/`、`docs/`、`scripts/`、`tests/`、`.github/workflows/`。
- 新增 `skills/wmux-best-practice`：遷移自 [maze-coder](https://github.com/bext1998/maze-coder) `extensions/wmux`（`wmux` 技能），僅更新 frontmatter、標題、描述與路徑引用，未縮減任何觸發情境、操作能力或安全邊界。
- 新增 `skills/wmux-coordinator`：遷移自 maze-coder `extensions/wmux-orchestrator`（`wmux-orchestrator` 技能），僅更新 frontmatter、標題、描述與對 `wmux-best-practice` 的相對路徑引用，未縮減 Worker Registry、狀態模型、失敗/blocked 升級規則或 per-harness 適配層。
- 以 wmux `v0.41.0`（annotated tag SHA `60127c5d37ec9d24ae6640cac1f5793a20e76ac6`，commit `390aa5beef1c9dfc07ebe02db3db3c8229462260`，platform `win32`，capabilities `protocols: ["v1","v2"]` / `features: ["workspaces","splits","notifications"]`）重新核對兩個技能的既有結論，並記錄新發現但未實測的 CLI 表面（`report-agent`/`answer-agent`/`report-metadata`/`report-session`/`release-agent`/`agent-state`）。
- 新增 `docs/SPEC.md`、`docs/skill-authoring-rules.md`、`docs/testing.md`、`docs/install.md`、`docs/migration.md`、`AGENTS.md`、`CLAUDE.md`。
- 新增通用安裝腳本 `scripts/install.sh`，可安裝兩個技能到任意目標技能目錄。
- 新增 `tests/` 下的靜態驗證腳本與 `.github/workflows/ci.yml`，於 PR 與 push `main` 時執行。

### Notes

- 尚未發布 `v0.0.1` tag / GitHub Release；版本號與發布流程見 [docs/SPEC.md](docs/SPEC.md#發布流程)。
