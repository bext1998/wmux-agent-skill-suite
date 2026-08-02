#!/usr/bin/env bash
# 驗證沒有非預期殘留的舊名稱 wmux-orchestrator（作為技能名/資料夾名）、舊安裝路徑、maze-* 前綴。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

if [ -d "${repo_root}/skills/wmux-orchestrator" ] || [ -d "${repo_root}/skills/wmux" ]; then
  echo "FAIL: skills/ 下殘留舊名稱資料夾 (wmux 或 wmux-orchestrator)"
  fail=1
fi

if find "${repo_root}/skills" -name "SKILL.md" -exec grep -l '^name: wmux-orchestrator$\|^name: wmux$' {} \; | grep -q .; then
  echo "FAIL: 有 SKILL.md 的 frontmatter name 仍是舊名稱 (wmux / wmux-orchestrator)"
  fail=1
fi

# 舊安裝路徑範例（extensions/wmux, extensions/wmux-orchestrator）不應出現在實際技能內容/安裝腳本/CI 內。
# docs/migration.md、README.md 的「從舊名稱遷移」段落、CHANGELOG.md 的歷史更名說明允許提及舊路徑，
# 那是給使用者遷移用的必要說明，不是非預期殘留。
legacy_path_hits="$(grep -rIl --exclude-dir=.git \
  -e 'extensions/wmux-orchestrator' \
  -e 'extensions/wmux[^-]' \
  -e 'extensions/wmux$' \
  "${repo_root}/skills" "${repo_root}/scripts" "${repo_root}/.github" \
  "${repo_root}/docs/SPEC.md" "${repo_root}/docs/testing.md" \
  "${repo_root}/docs/install.md" "${repo_root}/docs/skill-authoring-rules.md" \
  2>/dev/null || true)"
if [ -n "${legacy_path_hits}" ]; then
  echo "FAIL: 發現舊安裝路徑殘留引用:"
  echo "${legacy_path_hits}"
  fail=1
fi

# maze-* 技能前綴不應出現在 skills/ 下
if find "${repo_root}/skills" -mindepth 1 -maxdepth 1 -iname 'maze-*' | grep -q .; then
  echo "FAIL: skills/ 下發現 maze-* 前綴殘留"
  fail=1
fi

if [ "${fail}" -eq 0 ]; then
  echo "PASS: 無舊名稱/舊路徑/maze-* 殘留"
fi
exit "${fail}"
