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

### 環境需求：GNU coreutils `realpath`

`scripts/install.sh` 的路徑安全檢查（拒絕根目錄、拒絕跟技能來源目錄重疊等）依賴 **GNU coreutils 版 `realpath` 的 `-m` 旗標**（在完全不建立任何檔案的前提下正規化尚未存在的路徑）。腳本執行前會先做一次 capability probe 確認 `-m` 可用，不支援時會明確報錯並中止，不會靜默退化成不安全的行為。

- **Linux（大多數發行版）／Windows Git Bash（MSYS）**：內建的 `realpath` 就是 GNU coreutils 版，通常不需要額外安裝。
- **macOS**：系統內建的 `realpath` 是 BSD 版，**不支援 `-m`**。需要另外安裝 GNU coreutils（例如 `brew install coreutils`），並確保 PATH 上優先找到的是 GNU 版（`brew` 安裝後預設會裝成 `grealpath`；若要讓腳本直接用 `realpath` 這個名字找到它，需要自行建立別名或調整 PATH，例如 `brew install coreutils` 後常見做法是把 `$(brew --prefix coreutils)/libexec/gnubin` 加進 PATH 最前面）。

### Windows 專屬路徑處理的適用範圍

`scripts/install.sh` 針對 Windows/Git Bash（MSYS）與 Cygwin 環境（以 `uname -s` 判斷）另外做了兩項處理，只在這類環境下生效，不影響 Linux/macOS 上的行為：

1. 把呼叫端傳入的 Windows 原生 drive-letter 路徑（`D:/foo`、`D:\foo`）正規化成 MSYS 形式（`/d/foo`）後再做重疊檢查，並明確拒絕 bare drive root（`D:/`、`C:/` 等）。
2. 邊界比對時忽略大小寫——NTFS（Windows 原生磁碟區，以及 Git Bash/Cygwin 掛載出來的檔案系統）預設「不分大小寫但保留大小寫」，即使 drive-letter 已經正規化一致，路徑其餘部分大小寫不同仍可能指向磁碟上同一個實際目錄；忽略大小寫比對可以正確偵測出這種重疊。真正的安裝路徑（`mkdir`/`cp` 實際使用的路徑）仍保留呼叫端原本輸入的大小寫，只有「跟技能來源目錄是否重疊」這個安全判斷本身忽略大小寫。

在真正的 POSIX 檔案系統（Linux ext4 等，大小寫不同就是不同目錄）上，以上兩項處理都不會套用，避免把使用者刻意分開、只是大小寫不同或字面上長得像 drive-letter 的路徑誤判成危險路徑而拒絕。

### 目標路徑的其他限制

- **不接受單一 `-` 以外的特殊字元陷阱**：安裝腳本內部一律用已經正規化過的絕對路徑（並加上 `--`）呼叫 `mkdir`/`cd`，不會把使用者輸入的原始字串直接傳給這些指令，因此目標路徑就算長得像指令選項（例如單一 `-`）也會被當成一個普通、正確驗證過的目錄名稱安全處理，不會誤觸 Bash `cd -`（切換到 `$OLDPWD`）之類的特例行為。
- **只在 MSYS 拒絕 Windows drive-relative 路徑**：`C:foo`、`C:.` 這種「drive letter 後面不是 `/` 或 `\`」的寫法，在 Windows 路徑語意裡代表「相對於 `C:` 磁碟機當下的工作目錄」，跟 `C:/foo`（drive-絕對路徑）意義不同，而 Bash 沒有可靠、可攜的方式知道某個磁碟機當下的工作目錄是什麼。安裝腳本會明確拒絕這種輸入（只在 MSYS 環境下），請改用帶斜線的絕對路徑（如 `C:/foo`）或一般相對路徑；`C:`（沒有任何路徑內容）則視為 bare drive root 處理，同樣被拒絕。

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
