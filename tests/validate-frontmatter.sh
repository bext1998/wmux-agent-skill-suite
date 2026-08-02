#!/usr/bin/env bash
# 驗證每個 skills/*/SKILL.md 都有合法 YAML frontmatter，且 name 欄位與資料夾名稱一致。
# 「合法」由 tests/lib/parse-frontmatter.js 透過真正合規的 YAML parser（js-yaml，
# 見 package.json/package-lock.json 鎖定版本）解析判定，不只是用 grep 找
# name/description 這兩個字串是否出現。執行前需要先 `npm ci` 安裝依賴。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
parser="${repo_root}/tests/lib/parse-frontmatter.js"
fail=0

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: 需要 node 才能真正解析 YAML frontmatter，但找不到 node" >&2
  exit 1
fi

if [ ! -d "${repo_root}/node_modules/js-yaml" ]; then
  echo "FAIL: 找不到 node_modules/js-yaml，請先在 repo 根目錄執行 'npm ci' 安裝依賴" >&2
  exit 1
fi

for skill_dir in "${repo_root}"/skills/*/; do
  skill_name="$(basename "${skill_dir}")"
  skill_file="${skill_dir}SKILL.md"

  if [ ! -f "${skill_file}" ]; then
    echo "FAIL: ${skill_file} 不存在"
    fail=1
    continue
  fi

  # 先跑一次不帶 field 的模式，只是用來在解析失敗時取得完整錯誤訊息；
  # name/description 的實際值改用各自獨立的 field 呼叫取得，而不是對同一份
  # 多行 stdout 按行號切——parser 已經保證 name 不含 CR/LF，每個 field 呼叫的
  # 輸出本身就是單行、無歧義，不需要再靠行號對應。
  if ! parse_error="$(node "${parser}" "${skill_file}" 2>&1 1>/dev/null)"; then
    echo "FAIL: ${skill_file} frontmatter 解析失敗: ${parse_error}"
    fail=1
    continue
  fi

  fm_name="$(node "${parser}" "${skill_file}" name)"
  fm_desc_present="$(node "${parser}" "${skill_file}" description-ok)"

  if [ "${fm_name}" != "${skill_name}" ]; then
    echo "FAIL: ${skill_file} frontmatter name='${fm_name}' 與資料夾名稱 '${skill_name}' 不一致"
    fail=1
  fi

  if [ "${fm_desc_present}" != "1" ]; then
    echo "FAIL: ${skill_file} frontmatter 缺少非空的 description 欄位"
    fail=1
  fi
done

if [ "${fail}" -eq 0 ]; then
  echo "PASS: frontmatter 驗證通過"
fi
exit "${fail}"
