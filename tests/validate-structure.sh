#!/usr/bin/env bash
# 驗證必要檔案與資料夾存在。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

required_files=(
  "README.md"
  "LICENSE"
  "CHANGELOG.md"
  "AGENTS.md"
  "CLAUDE.md"
  "docs/SPEC.md"
  "docs/skill-authoring-rules.md"
  "docs/testing.md"
  "docs/install.md"
  "docs/migration.md"
  "scripts/install.sh"
  "skills/wmux-best-practice/SKILL.md"
  "skills/wmux-coordinator/SKILL.md"
)

for f in "${required_files[@]}"; do
  if [ ! -f "${repo_root}/${f}" ]; then
    echo "FAIL: 缺少必要檔案 ${f}"
    fail=1
  fi
done

required_dirs=(skills docs scripts tests .github/workflows)
for d in "${required_dirs[@]}"; do
  if [ ! -d "${repo_root}/${d}" ]; then
    echo "FAIL: 缺少必要目錄 ${d}"
    fail=1
  fi
done

if [ "${fail}" -eq 0 ]; then
  echo "PASS: 目錄/檔案結構驗證通過"
fi
exit "${fail}"
