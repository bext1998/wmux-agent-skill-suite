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

本 repository 建立時以 wmux 官方最新正式版本作為適配與驗證基準，記錄於各技能檔案的「版本重新驗證紀錄」段落與 [CHANGELOG.md](CHANGELOG.md)。

## 授權

[MIT License](LICENSE)
