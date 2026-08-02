#!/usr/bin/env bash
# 將 wmux-best-practice 與 wmux-coordinator 兩個技能安裝到指定的技能目錄。
# 用法：install.sh <目標技能根目錄>
# 範例：install.sh ~/.claude/skills
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "用法: $0 <目標技能根目錄>" >&2
  exit 1
fi

target_root="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
skills_src="${repo_root}/skills"

if [ ! -d "${skills_src}/wmux-best-practice" ] || [ ! -d "${skills_src}/wmux-coordinator" ]; then
  echo "錯誤: 找不到 ${skills_src}/wmux-best-practice 或 ${skills_src}/wmux-coordinator" >&2
  exit 1
fi

mkdir -p "${target_root}"

for skill in wmux-best-practice wmux-coordinator; do
  dest="${target_root}/${skill}"
  rm -rf "${dest}"
  cp -r "${skills_src}/${skill}" "${dest}"
  echo "已安裝 ${skill} -> ${dest}"
done

echo "完成。兩個技能已同層安裝於: ${target_root}"
