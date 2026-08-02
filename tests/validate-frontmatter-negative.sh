#!/usr/bin/env bash
# 驗證 frontmatter 解析器（tests/lib/parse-frontmatter.js）真的在做結構化解析，
# 而不只是 grep 字串——對 malformed YAML 與 duplicate key 必須回報失敗。
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
parser="${repo_root}/tests/lib/parse-frontmatter.js"
fail=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

check_fails() {
  local label="$1" file="$2"
  if node "${parser}" "${file}" >/dev/null 2>&1; then
    echo "FAIL: ${label} 應該被判定為不合法，但解析器卻回報成功"
    fail=1
  fi
}

check_succeeds() {
  local label="$1" file="$2"
  if ! node "${parser}" "${file}" >/dev/null 2>&1; then
    echo "FAIL: ${label} 應該是合法 frontmatter，但解析器卻回報失敗"
    fail=1
  fi
}

# 情境 1：正常合法的 frontmatter（對照組，確保解析器本身沒壞掉）。
valid_file="${tmp_dir}/valid.md"
cat > "${valid_file}" <<'EOF'
---
name: example-skill
description: 這是一個正常的技能描述
---

# example-skill
EOF
check_succeeds "合法 frontmatter" "${valid_file}"

# 情境 2：malformed YAML（未閉合的引號），純 grep name/description 的舊實作看不出問題。
malformed_file="${tmp_dir}/malformed.md"
cat > "${malformed_file}" <<'EOF'
---
name: example-skill
description: "未閉合的引號一路吃到檔案結尾
---

# example-skill
EOF
check_fails "malformed YAML（未閉合引號）" "${malformed_file}"

# 情境 3：duplicate key（name 出現兩次），純 grep 看到 name/description 字串都在，
# 但這其實不是合法、無歧義的 mapping。
duplicate_file="${tmp_dir}/duplicate.md"
cat > "${duplicate_file}" <<'EOF'
---
name: example-skill
description: 第一個描述
name: another-name
---

# example-skill
EOF
check_fails "duplicate key（name 重複）" "${duplicate_file}"

# 情境 4：frontmatter 是合法 YAML，但不是 mapping（是一個 list）。
list_file="${tmp_dir}/list.md"
cat > "${list_file}" <<'EOF'
---
- name
- description
---

# example-skill
EOF
check_fails "frontmatter 不是 mapping（是 list）" "${list_file}"

# 情境 5：flow collection 未閉合（不合法 YAML）。code review 發現先前的自製 parser
# 只認 quoted scalar 的未閉合，會漏掉這種未閉合——必須用真正的 YAML parser 才抓得到。
unterminated_flow_file="${tmp_dir}/unterminated-flow.md"
cat > "${unterminated_flow_file}" <<'EOF'
---
name: example-skill
description: [unterminated
---

# example-skill
EOF
check_fails "malformed YAML（未閉合的 flow collection）" "${unterminated_flow_file}"

# 情境 6：合法 YAML（YAML 單引號字串內用連續兩個單引號表示一個字面單引號）。
# code review 發現先前的自製 parser 會誤判這是不合法輸入而拒絕——必須接受它。
doubled_quote_file="${tmp_dir}/doubled-quote.md"
printf -- '---\nname: example-skill\ndescription: '"'"'It'"''"'s valid YAML'"'"'\n---\n\n# example-skill\n' > "${doubled_quote_file}"
check_succeeds "合法 YAML（單引號字串內的連續單引號跳脫）" "${doubled_quote_file}"

# 情境 7：name 欄位是合法 YAML，但值本身含換行（literal block scalar `|`）。
# code review 發現：舊版 parse-frontmatter.js 把 name 印在 stdout 第一行、
# description 是否非空印在第二行，呼叫端單純按行號取值——如果 name 本身跨行，
# 就能在 name 的第二行塞進偽造的 '1'，讓「description 缺失」被誤判成「存在」。
# 這裡刻意讓 description 缺失、且 name 展開後第二行是 '1'：如果解析器沒有明確
# 拒絕含換行的 name，validate-frontmatter.sh 舊的行號解析就會被騙過。
multiline_name_file="${tmp_dir}/multiline-name.md"
cat > "${multiline_name_file}" <<'EOF'
---
name: |
  example-skill
  1
---

# example-skill
EOF
check_fails "name 欄位含換行（multiline name 注入）" "${multiline_name_file}"

# 情境 8：block scalar（`description: |`）內部剛好有一行縮排後整行只剩 "---"
# （合法的 YAML 內容，只是恰好長得像分隔線）。舊版用 `trim()` 比對分隔線，會把這行
# 誤判成 frontmatter 結尾而提早截斷，悄悄吃掉分隔線之後、block scalar 裡原本還沒
# 結束的內容，且不會報錯（截斷後的殘骸通常仍是合法 YAML）。修正後的分隔線比對要求
# 整行「頂格、恰好是 ---」，因此必須正確跳過這行縮排的 "---"，找到後面真正頂格的
# 結尾分隔線，並保留 description 裡分隔線前後的完整內容。
indented_delimiter_file="${tmp_dir}/indented-delimiter.md"
cat > "${indented_delimiter_file}" <<'EOF'
---
name: example-skill
description: |
  first line
  ---
  second line after the indented look-alike delimiter
---

# example-skill
EOF
check_succeeds "block scalar 內縮排的 '---'（非真正分隔線）" "${indented_delimiter_file}"
# 直接呼叫 parser 本身的 description-base64 輸出比對完整內容，而不是在測試裡另外
# 獨立重寫一份「正確」的擷取邏輯——先前的寫法用 node -e 內嵌一份跟 parser 分開維護
# 的擷取器（同樣用 `lines[i] === "---"` 找結尾），如果 parser 本體退回用 trim() 比對
# （重新引入 bug），這個獨立重寫的擷取器不會受影響、仍然正確，測試就會誤判通過，
# 完全沒測到 parser 實際的行為。改成直接讀 parser 的輸出，parser 退回 trim() 時
# description 會被截斷、輸出的 base64 解碼後就不會等於期望的完整內容，測試才會真的抓到。
expected_description="$(printf 'first line\n---\nsecond line after the indented look-alike delimiter\n')"
actual_description_b64="$(node "${parser}" "${indented_delimiter_file}" description-base64 2>/dev/null)"
actual_description="$(printf '%s' "${actual_description_b64}" | base64 -d 2>/dev/null)"
if [ "${actual_description}" != "${expected_description}" ]; then
  echo "FAIL: block scalar 內縮排的 '---' 測試——parser 實際輸出的 description 內容不符預期（可能被提早截斷，遺失了分隔線之後的那行）"
  echo "  期望: $(printf '%s' "${expected_description}" | base64)"
  echo "  實際: ${actual_description_b64}"
  fail=1
fi

# 情境 9：frontmatter 頂層是合法 YAML，但不是 mapping，而是一個會被 js-yaml 隱式
# `!!timestamp` tag 解析成 JS `Date` 物件的純量（例如整份 frontmatter 只有一行
# ISO-8601 日期）。`Date` 的 `typeof` 也是 `"object"`、也不是 array，用舊版
# `typeof mapping !== "object" || Array.isArray(mapping)` 檢查會誤判這是「合法
# mapping（只是沒有 name/description 欄位）」而放行，實際上頂層根本不是 mapping。
timestamp_scalar_file="${tmp_dir}/timestamp-scalar.md"
cat > "${timestamp_scalar_file}" <<'EOF'
---
2026-08-02
---

# example-skill
EOF
check_fails "frontmatter 頂層不是 mapping（是 timestamp Date scalar）" "${timestamp_scalar_file}"

if [ "${fail}" -eq 0 ]; then
  echo "PASS: frontmatter 解析器負向測試通過"
fi
exit "${fail}"
