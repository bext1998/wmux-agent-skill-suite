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

if [ -z "${target_root}" ]; then
  echo "錯誤: 目標技能根目錄不可為空字串" >&2
  exit 1
fi

if ! command -v realpath >/dev/null 2>&1; then
  echo "錯誤: 需要 GNU coreutils 的 realpath 指令進行路徑安全檢查，但找不到 realpath" >&2
  exit 1
fi

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -P "${script_dir}/.." && pwd -P)"

if [ ! -d "${repo_root}/skills" ]; then
  echo "錯誤: 找不到 ${repo_root}/skills" >&2
  exit 1
fi

# 解析 skills/ 本身的真實路徑（skills_src）——skills/ 這個目錄本身也可能是 symlink，
# 只解析 repo_root 不夠，要對 skills/ 再做一次 cd -P/pwd -P，否則後面拿 skills_src
# 跟目標路徑比對重疊時，實際比對到的會是 symlink 路徑而不是真正的來源位置，漏判重疊。
skills_src="$(cd -P "${repo_root}/skills" && pwd -P)"

# `cd -P && pwd -P` 在 Windows/Git Bash（MSYS）環境下固定輸出 MSYS 形式的路徑
# （例如 /d/foo），但 `realpath -m` 對「尚未存在、無法真的 cd 進去」的目標路徑只做
# 純文字正規化，遇到呼叫端直接傳入 Windows 原生 drive-letter 形式（如 D:/foo、
# D:\foo）時，會原樣保留 drive-letter 前綴，不會轉成 /d/foo。這造成同一個實際目錄
# 在兩種正規化路徑下輸出的字串不同，用字串比對做的邊界檢查（見下方
# check_target_boundaries）會漏判重疊——呼叫端只要用 Windows 原生形式指向
# skills_src 底下一個原本不存在的子目錄，就能繞過「mkdir 前拒絕」的檢查，讓
# mkdir -p 先把新目錄建到技能來源目錄裡面，才在事後的 cd -P/pwd -P 二次確認
# （那時目錄已經存在，才會被強制轉成 MSYS 形式）被抓到，為時已晚。
# 這個函式把常見的 Windows 原生 drive-letter 路徑（C:/foo、C:\foo、C:foo、單獨的
# C:、C:/）正規化成 MSYS 形式（/c/foo、/c），讓它可以跟 skills_src 用同一種字串
# 表示法比較；不含 drive-letter 前綴的路徑（含所有真正的 POSIX 路徑）原樣輸出，
# 不受影響、不會誤傷。
to_msys_form() {
  local p="$1"
  if [[ "${p}" =~ ^([A-Za-z]):[/\\]?(.*)$ ]]; then
    local drive rest
    drive="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    rest="${BASH_REMATCH[2]//\\//}"
    if [ -z "${rest}" ]; then
      p="/${drive}"
    else
      p="/${drive}/${rest}"
    fi
  fi
  printf '%s' "${p}"
}

skills_src="$(to_msys_form "${skills_src}")"

if [ ! -d "${skills_src}/wmux-best-practice" ] || [ ! -d "${skills_src}/wmux-coordinator" ]; then
  echo "錯誤: 找不到 ${skills_src}/wmux-best-practice 或 ${skills_src}/wmux-coordinator" >&2
  exit 1
fi

# 邊界檢查函式：candidate 是一個已經正規化過的絕對路徑，檢查它是否為根目錄、
# 或跟本 repo 的技能來源目錄 skills_src 重疊（相同、互為子目錄都算重疊）。
check_target_boundaries() {
  local candidate="$1"
  # 去掉候選路徑尾端的斜線，方便跟下面的 drive-root pattern（/c、/d，不帶尾端
  # 斜線）比較；skills_src、resolved_root 等其他候選值本身不帶尾端斜線，用同一種
  # 去尾斜線後的形狀比較才不會漏判。
  local candidate_trimmed="${candidate%/}"

  if [ -z "${candidate}" ] || [ "${candidate}" = "/" ] || [[ "${candidate_trimmed}" =~ ^/[A-Za-z]$ ]]; then
    echo "錯誤: 目標技能根目錄解析後是根目錄或 Windows drive root '${candidate}'，拒絕安裝以避免污染整個磁碟機或根目錄下的內容" >&2
    return 1
  fi

  case "${candidate}/" in
    "${skills_src}/")
      echo "錯誤: 目標技能根目錄 '${candidate}' 與本 repo 的技能來源目錄 '${skills_src}' 相同，拒絕安裝" >&2
      return 1
      ;;
    "${skills_src}/"*)
      echo "錯誤: 目標技能根目錄 '${candidate}' 位於本 repo 的技能來源目錄 '${skills_src}' 之下，拒絕安裝" >&2
      return 1
      ;;
  esac
  case "${skills_src}/" in
    "${candidate}/"*)
      echo "錯誤: 本 repo 的技能來源目錄 '${skills_src}' 位於目標技能根目錄 '${candidate}' 之下，拒絕安裝" >&2
      return 1
      ;;
  esac

  return 0
}

# 先用 `realpath -m` 在完全不建立任何檔案/目錄的前提下，把 target_root 正規化成
# 絕對路徑：已存在的路徑前綴（含 symlink）會被解析成真實路徑，尚不存在的後段只會
# 被文字拼接（因為還不存在，不可能是 symlink）。用這個「假設性解析結果」先做危險
# 路徑檢查，通過才呼叫 mkdir -p——避免「先建立/污染路徑，檢查沒過才發現為時已晚」
# 的問題（例如 target 指向 skills_src 底下一個原本不存在的子目錄時，若先 mkdir -p
# 會在被拒絕之前就把該子目錄建立在來源目錄底下）。
hypothetical_root="$(to_msys_form "$(realpath -m -- "${target_root}")")"

if ! check_target_boundaries "${hypothetical_root}"; then
  exit 1
fi

mkdir -p "${target_root}"
resolved_root="$(to_msys_form "$(cd -P "${target_root}" && pwd -P)")"

# mkdir -p 之後路徑確實存在了，用 cd -P/pwd -P 重新解析一次做最終確認：防禦性地
# 不假設上面對 hypothetical_root 的檢查已經涵蓋所有情況（例如 target_root 內含
# 尚未處理過的特殊路徑片段），確認結果不一致時一律以更保守的方式失敗。
if ! check_target_boundaries "${resolved_root}"; then
  exit 1
fi

for skill in wmux-best-practice wmux-coordinator; do
  dest="${resolved_root}/${skill}"

  # 邊界檢查：dest 必須確實落在 resolved_root 之下，且不得等於或高於 resolved_root，
  # 避免路徑組合意外算出根目錄或 resolved_root 以外的位置後被 rm -rf。
  case "${dest}" in
    "${resolved_root}/"*) : ;;
    *)
      echo "錯誤: 解析後的安裝路徑 '${dest}' 不在目標根目錄 '${resolved_root}' 之下，拒絕安裝" >&2
      exit 1
      ;;
  esac
  if [ -z "${dest}" ] || [ "${dest}" = "/" ]; then
    echo "錯誤: 解析後的安裝路徑不合法: '${dest}'" >&2
    exit 1
  fi

  rm -rf "${dest}"
  cp -r "${skills_src}/${skill}" "${dest}"
  echo "已安裝 ${skill} -> ${dest}"
done

echo "完成。兩個技能已同層安裝於: ${target_root}"
