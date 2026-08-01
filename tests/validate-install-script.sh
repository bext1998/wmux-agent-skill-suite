#!/usr/bin/env bash
# 驗證通用安裝腳本可以把兩個技能安裝進自訂臨時目錄。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

bash "${repo_root}/scripts/install.sh" "${tmp_dir}"

for skill in wmux-best-practice wmux-coordinator; do
  if [ ! -f "${tmp_dir}/${skill}/SKILL.md" ]; then
    echo "FAIL: 安裝後找不到 ${tmp_dir}/${skill}/SKILL.md"
    fail=1
    continue
  fi
  if ! diff -q "${tmp_dir}/${skill}/SKILL.md" "${repo_root}/skills/${skill}/SKILL.md" >/dev/null; then
    echo "FAIL: 安裝後 ${skill}/SKILL.md 內容與來源不一致"
    fail=1
  fi
done

if [ "${fail}" -eq 0 ]; then
  echo "PASS: 安裝腳本驗證通過"
fi
exit "${fail}"
