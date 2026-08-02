#!/usr/bin/env bash
# 依序執行本目錄下所有驗證腳本。
set -uo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0

for script in \
  validate-structure.sh \
  validate-frontmatter.sh \
  validate-references.sh \
  validate-no-legacy-names.sh \
  validate-install-script.sh
do
  echo "== ${script} =="
  if ! bash "${test_dir}/${script}"; then
    fail=1
  fi
  echo
done

exit "${fail}"
