# 從 maze-coder 舊技能遷移

`maze-coder` repository 原本以 `extensions/wmux`（技能名稱 `wmux`）與 `extensions/wmux-orchestrator`（技能名稱 `wmux-orchestrator`）提供這兩個技能。自本 repository 建立起，這兩個技能改由 `wmux-agent-skill-suite` 獨立維護，並更名為：

| 舊名稱 | 新名稱 |
|---|---|
| `wmux` | `wmux-best-practice` |
| `wmux-orchestrator` | `wmux-coordinator` |

`maze-coder` 不再提供這兩個技能的副本；請改為安裝本 repository 的版本。

## 遷移步驟

1. **移除舊技能安裝**：找到先前安裝 `wmux`／`wmux-orchestrator` 的位置（例如 `~/.claude/skills/wmux/`、`~/.claude/skills/wmux-orchestrator/`、對應的 Codex/OpenCode/Pi 技能目錄），整份資料夾刪除。
2. **安裝新技能**：依 [docs/install.md](install.md) 的安裝腳本或手動複製方式，安裝 `wmux-best-practice` 與 `wmux-coordinator`，兩者需同層放置。
3. **更新任何寫死舊路徑的自動化**：若你的專案（例如某個 CLAUDE.md、AGENTS.md 或安裝腳本）曾經寫死 `extensions/wmux`、`~/.claude/skills/wmux/` 等舊路徑，改為指向本 repository 的 `skills/wmux-best-practice`、`skills/wmux-coordinator` 或安裝後的新路徑。

## 不得同時安裝新舊名稱

**不要**同時保留舊技能（`wmux`／`wmux-orchestrator`）與新技能（`wmux-best-practice`／`wmux-coordinator`）。原因：

- 兩者的觸發描述（frontmatter `description`）高度重疊，同時安裝會讓 coding agent 對同一個情境重複比對兩份技能，增加誤判與重複觸發的風險。
- 舊技能已不再維護（不會再收到 wmux 版本更新、行為修正），繼續保留只會讓使用者誤以為內容仍是最新。

遷移完成後，請確認舊技能資料夾已從所有安裝目錄移除，再開始使用新技能。
