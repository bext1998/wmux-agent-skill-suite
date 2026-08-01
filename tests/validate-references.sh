#!/usr/bin/env bash
# 驗證 wmux-coordinator 對 wmux-best-practice 的相對引用存在，且沒有指向舊路徑 ../wmux/ 的殘留引用。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

coord_file="${repo_root}/skills/wmux-coordinator/SKILL.md"
target_file="${repo_root}/skills/wmux-best-practice/SKILL.md"

if [ ! -f "${coord_file}" ]; then
  echo "FAIL: ${coord_file} 不存在"
  exit 1
fi

if [ ! -f "${target_file}" ]; then
  echo "FAIL: 被引用的 ${target_file} 不存在"
  fail=1
fi

if ! grep -q '\.\./wmux-best-practice/SKILL\.md' "${coord_file}"; then
  echo "FAIL: ${coord_file} 找不到對 ../wmux-best-practice/SKILL.md 的相對引用"
  fail=1
fi

if grep -q '\.\./wmux/' "${coord_file}"; then
  echo "FAIL: ${coord_file} 仍殘留舊路徑引用 ../wmux/"
  fail=1
fi

if [ "${fail}" -eq 0 ]; then
  echo "PASS: 相對引用驗證通過"
fi
exit "${fail}"
