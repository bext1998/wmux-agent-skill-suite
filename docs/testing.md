# 測試方式

## 1. 靜態 CI 驗證（GitHub Actions，任何平台可跑）

由 `.github/workflows/ci.yml` 執行，觸發時機：對 `main` 的 Pull Request、push 到 `main`。驗證項目對應 `tests/` 下的腳本：

- `tests/validate-frontmatter.sh`：每個 `skills/*/SKILL.md` 都有合法 YAML frontmatter（用 `tests/lib/parse-frontmatter.js` 透過真正合規的 YAML parser `js-yaml` 解析，見 `package.json`/`package-lock.json`），且 `name` 欄位與所在資料夾名稱一致。
- `tests/validate-frontmatter-negative.sh`：`tests/lib/parse-frontmatter.js` 對 malformed YAML（未閉合的引號/flow collection）、duplicate key、frontmatter 不是 mapping（含 name 欄位含 CR/LF 的 multiline name 注入、frontmatter 頂層被 js-yaml 隱式解析成 `!!timestamp` Date scalar 而非 mapping）這幾種不合法輸入必須回報失敗；對合法 YAML（含單引號字串內以連續單引號跳脫、block scalar 內部縮排後剛好整行只有 `---` 但不是真正分隔線）必須成功解析、且不能提早截斷內容——這項直接呼叫 parser 的 `description-base64` 輸出（把 description 原始值 base64 編碼後印成單行，供測試解碼比對，見 `parse-frontmatter.js` 內的說明），比對完整內容是否與期望值逐字相符，而不是在測試裡另外獨立重寫一份擷取邏輯（避免測試跟 parser 本體用不同邏輯各測各的，parser 退化也測不出來）。
- `tests/validate-structure.sh`：必要檔案存在（`README.md`、`LICENSE`、`CHANGELOG.md`、`AGENTS.md`、`CLAUDE.md`、`docs/SPEC.md`、兩個技能的 `SKILL.md`）；資料夾名稱正確（`skills/wmux-best-practice`、`skills/wmux-coordinator`）。
- `tests/validate-references.sh`：`wmux-coordinator/SKILL.md` 內對 `wmux-best-practice` 的相對引用路徑真實存在，且不存在任何指向 `../wmux/` 舊路徑的殘留引用。
- `tests/validate-no-legacy-names.sh`：全 repo 範圍內不存在舊名稱 `wmux-orchestrator`（作為技能名稱/資料夾名，不含本說明文件、CHANGELOG 內對歷史更名的必要說明）、舊安裝路徑範例，以及 `maze-*` 技能前綴殘留。
- `tests/validate-install-script.sh`：`scripts/install.sh` 可將兩個技能安裝到一個臨時目錄，且安裝後檔案內容與 `skills/` 來源一致。
- `tests/validate-install-script-negative.sh`：`scripts/install.sh` 對危險的 target（空字串、解析後為根目錄 `/`、解析後與本 repo 的技能來源目錄 `skills/` 重疊——含相同、互為父子、target 是指向來源的 symlink、`skills/` 本身是 symlink、Windows/Git Bash 原生 drive-letter 形式（`D:/...`）指向來源底下不存在的子目錄、target 本身就是 Windows drive root（`D:/`、`D:\`、`C:/` 等）、target 跟來源 `skills/` 大小寫不同但在 NTFS 上是磁碟上同一個目錄、target 是單一 `-`、target 是 Windows drive-relative 路徑（如 `C:foo`）等情況）必須明確拒絕（非零 exit code）或安全完成（不允許半成品/污染的中間狀態），且任何拒絕都必須發生在建立/污染任何路徑之前、不能造成既有內容被誤刪或技能來源目錄損毀。也反向驗證非 MSYS（真正的 POSIX 檔案系統）環境下，這些 Windows 專屬防護不會誤傷：字面上長得像 drive root／drive-relative 路徑的字串不會被誤判拒絕、跟來源只有大小寫不同（在 POSIX 上是不同目錄）的 target 能正常安裝成功。symlink 相關情境只在提供真正 POSIX symlink 語意的環境（例如 CI 的 ubuntu-latest）下才有意義；drive-letter/drive-root/drive-relative/大小寫不敏感相關情境只在 Windows/Git Bash（MSYS）或 Cygwin 環境下有意義；target 是單一 `-` 的情境是一般 Bash 行為（`cd -` 特例），不限 MSYS；驗證「非 MSYS 不誤傷」的情境則反過來只在非 MSYS 環境下有意義。與被測試的 `scripts/install.sh` 用同一種 `uname -s` 判斷方式決定是否適用，在不適用的環境會自動 SKIP 並註明原因。

本機執行（POSIX shell / Git Bash）：

```bash
npm ci
bash tests/run-all.sh
```

`tests/validate-frontmatter.sh` 需要先 `npm ci` 安裝鎖定版本的 `js-yaml` 依賴（見 `package.json`/`package-lock.json`），且需要 Node.js `>=24`（見 `package.json` 的 `engines`）；CI 已在 `.github/workflows/ci.yml` 設定 `actions/setup-node@v4`（`node-version: 24`）+ `npm ci`。

Windows 原生 PowerShell 環境無法直接跑上述 Bash 驗證時，改以 GitHub Actions 的執行結果為準；不建議在 PowerShell 下另外維護一份等效腳本（避免兩份驗證邏輯漂移）。

## 2. Windows wmux 實機驗證（手動，CI 不跑）

CI 只做靜態內容檢查，不會真的啟動 wmux 或操作 pane。任何會改變技能「行為結論」的修訂（旗標是否有效、忙碌/完成畫面呈現、per-harness 適配層等），都需要在真實 Windows + wmux 環境下手動驗證：

1. 確認本機 wmux 版本：`wmux identify` / `wmux capabilities`。
2. 依技能文件描述的流程，對真實 pane 執行對應指令，觀察實際回應與畫面呈現。
3. 將版本、tag/commit SHA、平台、capabilities 與觀察結果，記錄進對應技能檔案的「版本重新驗證紀錄」段落。
4. 若觀察結果與既有文件描述不一致，比照 `wmux-coordinator` 既有的「重要更正」寫法處理，不覆蓋、不刪除舊紀錄的脈絡。

這一步無法在 GitHub Actions 的 Linux/hosted runner 上執行（沒有 wmux 環境與互動 pane），因此不是 CI 的一部分；PR 描述應明確註明是否完成了這一步、或本次修訂不涉及行為結論變動。
