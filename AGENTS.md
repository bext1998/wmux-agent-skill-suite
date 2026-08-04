# AGENTS.md

本檔案供任何在本 repository 內工作的 coding agent（Codex、OpenCode、其他支援 `AGENTS.md` 慣例的工具）參考。內容與 `CLAUDE.md` 保持一致；兩份檔案的差異只在檔名，供不同工具各自的預設讀取慣例使用。

## 專案是什麼

`wmux-agent-skill-suite` 是兩個 `SKILL.md` 格式技能的獨立 repository：`wmux-best-practice`（wmux pane 操作 primitive）與 `wmux-coordinator`（跨 pane 派工協調，依賴前者）。完整規格見 [docs/SPEC.md](docs/SPEC.md)。

## 工作規則

1. **技能內容以實測為準**：修改 `skills/*/SKILL.md` 內任何行為結論前，先確認是否有對應的實測依據；沒有實測依據的內容要明確標註「未驗證」，不要包裝成確定結論。規則細節見 [docs/skill-authoring-rules.md](docs/skill-authoring-rules.md)。
2. **不縮減既有能力**：兩個技能都是從 maze-coder 遷移而來，遷移/更名/後續修訂都不得刪減既有段落、表格列或行為結論，只能以獨立段落追加或標註更正（沿用 `wmux-coordinator` 既有的「重要更正」寫法）。**例外**：版本驗證的過程與觀察紀錄（哪天測的、怎麼測的、用了哪些 ID）不算「既有段落」，一律寫進 `CHANGELOG.md`，不留在 SKILL.md 本體——SKILL.md 只保留 agent 執行任務時需要的結論，規則見 [docs/skill-authoring-rules.md](docs/skill-authoring-rules.md) 第 4、22 條。
3. **coding agent 中立**：技能內容不得引用特定 coding agent 的 plugin/hook/subagent API、模型名稱或固定安裝路徑。差異只放在 `docs/install.md`、`scripts/install.sh`。
4. **相對路徑引用**：`wmux-coordinator` 對 `wmux-best-practice` 的引用一律用相對路徑，修改檔案位置時要同步檢查引用是否仍然有效（`tests/validate-references.sh` 會檢查）。
5. **不建立與 maze-coder 的執行期相依**：不呼叫 maze-coder 的 script、不讀取其設定、不建立同步副本。
6. **修改後跑測試**：`bash tests/run-all.sh`（或依 [docs/testing.md](docs/testing.md) 分別執行）。涉及技能行為結論變動時，PR 描述需註明是否完成 Windows wmux 實機驗證。
7. **不自行建立 tag / GitHub Release**：發布由維護者在人工複審後執行，見 [docs/SPEC.md](docs/SPEC.md#發布流程)。

## 目錄結構

```
skills/wmux-best-practice/SKILL.md   # 基礎 pane 操作技能
skills/wmux-coordinator/SKILL.md     # 跨 pane 派工協調技能（引用上者）
docs/                                # 規格、撰寫規則、測試、安裝、遷移文件
scripts/install.sh                   # 通用安裝腳本
tests/                               # 靜態驗證腳本
.github/workflows/ci.yml             # CI
```
