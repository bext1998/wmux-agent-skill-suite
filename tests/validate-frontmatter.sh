#!/usr/bin/env bash
# 驗證每個 skills/*/SKILL.md 都有合法 YAML frontmatter，且 name 欄位與資料夾名稱一致。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

for skill_dir in "${repo_root}"/skills/*/; do
  skill_name="$(basename "${skill_dir}")"
  skill_file="${skill_dir}SKILL.md"

  if [ ! -f "${skill_file}" ]; then
    echo "FAIL: ${skill_file} 不存在"
    fail=1
    continue
  fi

  first_line="$(sed -n '1p' "${skill_file}")"
  if [ "${first_line}" != "---" ]; then
    echo "FAIL: ${skill_file} 第一行不是 '---'，frontmatter 缺失"
    fail=1
    continue
  fi

  # frontmatter 結束的第二個 '---' 行號
  end_line="$(awk 'NR>1 && $0=="---" {print NR; exit}' "${skill_file}")"
  if [ -z "${end_line}" ]; then
    echo "FAIL: ${skill_file} 找不到 frontmatter 結尾的 '---'"
    fail=1
    continue
  fi

  frontmatter="$(sed -n "2,$((end_line - 1))p" "${skill_file}")"

  fm_name="$(echo "${frontmatter}" | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
  fm_desc="$(echo "${frontmatter}" | grep -c '^description:' || true)"

  if [ "${fm_name}" != "${skill_name}" ]; then
    echo "FAIL: ${skill_file} frontmatter name='${fm_name}' 與資料夾名稱 '${skill_name}' 不一致"
    fail=1
  fi

  if [ "${fm_desc}" -lt 1 ]; then
    echo "FAIL: ${skill_file} frontmatter 缺少 description 欄位"
    fail=1
  fi
done

if [ "${fail}" -eq 0 ]; then
  echo "PASS: frontmatter 驗證通過"
fi
exit "${fail}"
