# 技能撰寫與維護規則

適用於本 repository 內 `skills/` 下的所有技能。

## 內容規則

1. **單一 source of truth**：每個技能只有一份 `SKILL.md`，不得為不同 coding agent 各寫一份分叉內容。coding agent 差異只透過安裝路徑/安裝腳本處理，見 [docs/install.md](install.md)。
2. **coding agent 中立**：技能內文不得引用特定 coding agent 的 plugin API、hook 機制、subagent 名稱、模型名稱或該 agent 專屬的固定安裝路徑。技能只能依賴：wmux CLI 本身、一般 shell（POSIX / PowerShell）、以及技能相對路徑引用。
3. **以實測為準，不是照抄 `--help`**：技能內的具體行為結論（旗標是否有效、預設落點、忙碌/完成畫面呈現等）必須來自實際呼叫過的觀察紀錄，不能只是重述 `wmux <command> --help` 的說明文字。無法驗證的部分要明確標註「未驗證」，不得包裝成確定結論。
4. **版本標註**：技能內以獨立段落（「驗證環境與適用範圍」/「版本重新驗證紀錄」）記錄驗證時的 wmux 版本、tag、commit SHA、平台、capabilities。版本落差時，既有結論一律視為未驗證，需要重新核對。
5. **相對路徑引用**：技能之間互相引用一律用相對路徑（如 `../wmux-best-practice/SKILL.md`），不得寫死絕對路徑或特定 coding agent 的安裝目錄。
6. **不擴大自身邊界**：技能明確排除的指令/操作（見各技能「不建議使用／超出範圍」「邊界」段落）不得因為後續修訂悄悄放寬，除非有新的實測紀錄支持並在文件中說明。

## 遷移/更名規則（本次適用）

- 更名只能調整：technical frontmatter（`name`、`description`）、標題、內部路徑引用（如 `../wmux/` → `../wmux-best-practice/`）、以及對應到新技能名稱的文字（如「本技能」等自我指涉）。
- 不得刪減任一段落、表格列、或既有實測紀錄；不得因為換到新 repo 就「順手」精簡內容。
- 新增內容（例如新版本的重新驗證紀錄）只能以獨立段落追加，不覆蓋既有實測紀錄；若新驗證推翻舊結論，需在文中明確寫「更正」並保留原結論的脈絡（沿用既有技能文件本身的做法，見 `wmux-coordinator` 的「重要更正」段落）。

## 維護規則

- 任何會改變技能行為結論的修訂，必須附上重新驗證的方式與觀察紀錄，不能只憑印象修改。
- 修訂 PR 需通過 [.github/workflows](../.github/workflows) 的靜態 CI；涉及行為結論變動的修訂，PR 描述需說明是否完成 Windows wmux 實機驗證（見 [docs/testing.md](testing.md)）。
- 新增技能（若未來擴充）需比照本文件規則撰寫，並在 `docs/SPEC.md`「技能責任邊界」表格中補上對應列。
