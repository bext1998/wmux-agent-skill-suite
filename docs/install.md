# 安裝方式

## 重要：兩個技能必須一起安裝、放在同一層

`skills/wmux-coordinator/SKILL.md` 用相對路徑 `../wmux-best-practice/SKILL.md` 引用 `wmux-best-practice`。這代表兩個技能必須：

1. **同時安裝**——只裝 `wmux-coordinator` 而不裝 `wmux-best-practice`，會讓其內部引用失效（找不到對應檔案，coding agent 無法讀到被引用的授權邊界/primitive 說明）。
2. **位於同一層目錄**——例如都在 `~/.claude/skills/` 下，成為 `~/.claude/skills/wmux-best-practice/` 與 `~/.claude/skills/wmux-coordinator/` 兩個平行資料夾，這樣相對路徑 `../wmux-best-practice/SKILL.md` 才能正確解析。不要把兩者裝進不同層級或不同 coding agent 的技能根目錄下。

## 通用安裝腳本

`scripts/install.sh` 可以把兩個技能複製到任意目標技能目錄：

```bash
# 用法：install.sh <目標技能根目錄>
bash scripts/install.sh ~/.claude/skills
bash scripts/install.sh ~/.codex/skills
```

腳本只做檔案複製（`skills/wmux-best-practice` 與 `skills/wmux-coordinator` → `<目標目錄>/wmux-best-practice`、`<目標目錄>/wmux-coordinator`），不下載任何遠端內容、不需要網路。若目標目錄下已存在同名資料夾，腳本會先安全地整份取代該資料夾內容（不做部分合併），執行前建議自行確認該目錄下沒有你想保留的手動修改。

## 各 coding agent 安裝範例

以下路徑為該工具常見的使用者層級技能目錄，實際位置請以對應工具文件為準；核心技能內容完全相同，差異只在路徑。

| Coding agent | 建議安裝目錄 | 指令 |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `bash scripts/install.sh ~/.claude/skills` |
| Codex | `~/.codex/skills/` | `bash scripts/install.sh ~/.codex/skills` |
| OpenCode | `~/.opencode/skills/`（或該工具設定的技能目錄） | `bash scripts/install.sh ~/.opencode/skills` |
| Pi | `~/.pi/skills/`（或該工具設定的技能目錄） | `bash scripts/install.sh ~/.pi/skills` |
| 其他支援 `SKILL.md` 格式的 coding agent | 該工具文件指定的技能目錄 | `bash scripts/install.sh <目標技能目錄>` |

Windows 上若使用 PowerShell 而非 Git Bash，可手動複製整個 `skills/wmux-best-practice` 與 `skills/wmux-coordinator` 資料夾到目標目錄（維持兩者同層），效果與執行 `scripts/install.sh` 相同：

```powershell
Copy-Item -Recurse -Force skills\wmux-best-practice "$env:USERPROFILE\.claude\skills\wmux-best-practice"
Copy-Item -Recurse -Force skills\wmux-coordinator "$env:USERPROFILE\.claude\skills\wmux-coordinator"
```

## 從舊名稱（`wmux`／`wmux-orchestrator`）遷移

見 [docs/migration.md](migration.md)。
