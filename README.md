# wmux-agent-skill-suite

專為wmux設計的AI Agent to Agent技能套件包。An AI Agent-to-Agent skill suite designed specifically for wmux.

兩個 coding-agent 中立、以 `SKILL.md` 格式撰寫的技能，用於 [wmux](https://github.com/amirlehmam/wmux) 多視窗終端機環境下的 pane 操作與跨 pane 派工協調。原為 [maze-coder](https://github.com/bext1998/maze-coder) 的 `extensions/wmux`、`extensions/wmux-orchestrator`，依該 repo Issue #31 遷移至本獨立 repository 並更名。

## 技能

| 技能 | 說明 | 目錄 |
|---|---|---|
| `wmux-best-practice` | 單一 pane 對其他 pane 的基礎操作：靜默環境偵測、四類操作授權分級、`ok:true` 陷阱、`--surface`/`--pane` 定位限制、pane-to-pane 訊息交接、pane/分頁建立與清除 | [`skills/wmux-best-practice`](skills/wmux-best-practice/SKILL.md) |
| `wmux-coordinator` | 建立在 `wmux-best-practice` 之上的 orchestrator：Worker Registry、單行任務協議（`TASK#`/`DONE#`/`FAILED#`/`BLOCKED#`）、派工/輪詢/升級規則、per-harness 適配層 | [`skills/wmux-coordinator`](skills/wmux-coordinator/SKILL.md) |

兩個技能**必須同時安裝、放在同一層目錄**——`wmux-coordinator` 用相對路徑引用 `wmux-best-practice`。詳見 [docs/install.md](docs/install.md)。

## 快速安裝

```bash
bash scripts/install.sh ~/.claude/skills   # 或任何其他目標技能目錄
```

支援任何解析 `SKILL.md` 格式的 coding agent（Claude Code、Codex、OpenCode、Pi 等）；各工具安裝路徑範例見 [docs/install.md](docs/install.md)。

從 maze-coder 舊技能（`wmux`／`wmux-orchestrator`）遷移，見 [docs/migration.md](docs/migration.md)。

## 文件

- [docs/SPEC.md](docs/SPEC.md) — 專案目標、非目標、技能責任邊界、相容性、安全規則、測試方式、發布流程
- [docs/skill-authoring-rules.md](docs/skill-authoring-rules.md) — 技能撰寫與維護規則
- [docs/testing.md](docs/testing.md) — 靜態 CI 驗證與 Windows wmux 實機驗證的區分與流程
- [docs/install.md](docs/install.md) — 各 coding agent 安裝範例
- [docs/migration.md](docs/migration.md) — 從舊名稱遷移指南
- [CHANGELOG.md](CHANGELOG.md) — 版本紀錄
- [AGENTS.md](AGENTS.md) / [CLAUDE.md](CLAUDE.md) — 給 coding agent 的專案守則

## 版本基準

本 repository 以一個經確認可正常使用的 wmux 正式版本作為適配與驗證基準，記錄於各技能檔案的「版本重新驗證紀錄」段落與 [CHANGELOG.md](CHANGELOG.md)。目前基準為 `v0.38.0`——建立時的最新正式版 `v0.41.0` 經使用者實際使用後回報有嚴重效能問題，因此未採用；`v0.41.0` 僅作為已知限制記錄，不是驗證基準。

`v0.42.0`（2026-08-03 發布）的官方 release notes 顯示已修好造成 `v0.41.0` 被放棄的那兩個效能問題，是未來升級驗證基準的候選版本。2026-08-04 已對本機實際運行的 `v0.42.0` 完成部分實機驗證（`identify`／`capabilities`／`--workspace`／`--pane` 旗標、`WMUX_SURFACE_ID` env 存在與繼承，詳見 `wmux-best-practice/SKILL.md` 的「版本重新驗證紀錄（v0.42.0）」），但兩個技能檔案記錄的其餘具體行為結論（非唯讀三類操作——可逆寫入／建立資源／破壞性、`ok: true` 可靠性、跨 pane 交接、per-harness 適配層等）**尚未在 v0.42.0 上逐項重新驗證**，因此整體驗證基準仍維持 `v0.38.0` 不變，只有上述已列出的項目升級為已對 `v0.42.0` 驗證。

## 授權

[MIT License](LICENSE)
