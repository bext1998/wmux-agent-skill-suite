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

# 只確認 realpath 指令存在不夠：本腳本的路徑安全檢查依賴 GNU coreutils realpath
# 專屬的 `-m` 旗標（在完全不建立任何檔案的前提下，把尚未存在的路徑正規化成絕對
# 路徑，見下方 hypothetical_root 的用法），BSD/macOS 系統內建的 realpath 不支援
# `-m`，遇到會直接報錯（unrecognized option）。用一個保證不出錯、不需要目標存在
# 的呼叫做 capability probe，而不是等真正跑到那一步才讓使用者看到不知所云的
# coreutils 錯誤訊息。見 docs/install.md 對這項需求的明確記錄。
if ! realpath -m -- "." >/dev/null 2>&1; then
  echo "錯誤: 系統的 realpath 不支援 GNU coreutils 的 '-m' 旗標（用來正規化尚未存在的路徑），本安裝腳本無法在此環境安全執行。BSD/macOS 內建的 realpath 不支援 -m；請安裝 GNU coreutils 版的 realpath（例如 macOS 上 'brew install coreutils' 後用 'grealpath'）並確保它是 PATH 上優先被找到的 realpath，見 docs/install.md。" >&2
  exit 1
fi

# 只在確認執行環境是 Windows/Git Bash（MSYS）或 Cygwin 時，才套用下面兩項
# Windows/NTFS 專屬的路徑處理：(a) 把原生 drive-letter 路徑正規化成 MSYS 形式、
# 拒絕 bare drive root；(b) 邊界比對時忽略大小寫。NTFS 預設是「不分大小寫但保留
# 大小寫」的檔案系統，這兩項處理只在這種檔案系統上才有意義；用 `uname -s`（POSIX
# 通用、macOS 也支援，比 `uname -o` 更可攜）判斷，避免在真正的 POSIX 檔案系統
# （例如 Linux ext4，大小寫不同就是不同目錄）上誤把使用者刻意分開、只是大小寫
# 不同的路徑當成同一個目錄而誤判重疊。
is_msys=0
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) is_msys=1 ;;
esac

# 只在 MSYS 拒絕 Windows drive-relative 路徑（drive letter 後面接的不是 / 或 \，
# 例如 "C:foo"、"C:."——在 Windows 路徑語意裡這代表「相對於 C: 磁碟機當下的工作
# 目錄」，不等於 "C:/foo" 這種 drive-絕對路徑）。這裡刻意不比照 "C:/foo" 那樣猜測
# 正規化成 "/c/foo"：`realpath -m` 對 "C:foo" 會回傳 "C:/foo"（幫它腦補了一個
# 斜線，等同誤判成 drive-絕對路徑），但實際負責建立目錄的 `mkdir`/`cd` 收到的是
# 原始字串 "C:foo"，MSYS 並不理解 Windows drive 語意，會把它當成 CWD-relative、
# 字面上含冒號的普通檔名處理——也就是說，邊界檢查驗證的位置（/c/foo）跟 mkdir
# 實際動作的位置（CWD 底下的 C:foo）完全對不上，讓邊界檢查形同虛設。實測重現過：
# 在 CWD 恰好是技能來源目錄本身的情況下，這會先把一個叫 "C:foo" 的目錄建到來源
# 目錄裡面（污染），雖然第二次檢查最終還是會抓到、讓整體安裝失敗，但污染已經
# 發生。與其嘗試比照 Windows 自己去解析「這個磁碟機當下的工作目錄是什麼」（bash
# 沒有可靠、可攜的方式知道這件事），更安全的作法是直接拒絕這種輸入，不做任何猜測。
# "C:"（drive letter 後面直接結尾，沒有任何內容）不受這個檢查影響——正規化後就是
# bare drive root "/c"，已經由下面 check_target_boundaries 的既有邏輯處理。
if [ "${is_msys}" -eq 1 ] && [[ "${target_root}" =~ ^[A-Za-z]:[^/\\] ]]; then
  echo "錯誤: 目標路徑 '${target_root}' 是 Windows drive-relative 路徑（drive letter 後面不是 / 或 \\），它的實際位置取決於該磁碟機當下的工作目錄，本腳本無法安全預先驗證，拒絕安裝。請改用帶斜線的絕對路徑（例如 '${target_root:0:2}/...'）。" >&2
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
# 表示法比較。只在確認執行環境是 MSYS/Cygwin（is_msys=1）時才做這個轉換——在真正
# 的 POSIX 平台（Linux/macOS）上，一個字面上長得像 "C:/foo" 的路徑幾乎不可能是
# 使用者真的想要的東西，但也不該被本腳本擅自重新解讀成 Windows drive letter；
# 維持原樣輸出才是對非 Windows 環境安全、不誤傷的作法。
to_msys_form() {
  local p="$1"
  if [ "${is_msys}" -eq 1 ] && [[ "${p}" =~ ^([A-Za-z]):[/\\]?(.*)$ ]]; then
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

# 邊界比對用的「比較 key」：只在 is_msys=1 時把整個路徑轉小寫。NTFS（Windows 原生
# 磁碟區、以及 Git Bash/Cygwin 掛載出來的檔案系統）預設不分大小寫但保留大小寫——
# 見下方「殘餘風險」的實測：即使 drive-letter 已經正規化一致，目錄路徑其餘部分的
# 大小寫仍可能不同卻指向磁碟上同一個實際目錄（例如
# /D/AGENTCODING/WMUX-AGENT-SKILL-SUITE/skills 與
# /d/AgentCoding/wmux-agent-skill-suite/skills 在 Windows 上是同一個目錄），純文字
# 比對會漏判這種重疊。這個函式只回傳「比較用」的字串，不能拿來當作實際要 mkdir/cp
# 的路徑——使用者原本輸入的大小寫仍要保留給實際檔案系統操作，只有拿來跟 skills_src
# 判斷是否重疊的那一步才需要／應該忽略大小寫。在真正的 POSIX 檔案系統
# （Linux ext4 等）上，大小寫不同就是不同目錄，這裡維持原樣、不做任何轉換。
to_compare_key() {
  local p="$1"
  if [ "${is_msys}" -eq 1 ]; then
    printf '%s' "${p}" | tr '[:upper:]' '[:lower:]'
  else
    printf '%s' "${p}"
  fi
}

skills_src="$(to_msys_form "${skills_src}")"

if [ ! -d "${skills_src}/wmux-best-practice" ] || [ ! -d "${skills_src}/wmux-coordinator" ]; then
  echo "錯誤: 找不到 ${skills_src}/wmux-best-practice 或 ${skills_src}/wmux-coordinator" >&2
  exit 1
fi

# 邊界檢查函式：candidate 是一個已經正規化過的絕對路徑，檢查它是否為根目錄、
# 或跟本 repo 的技能來源目錄 skills_src 重疊（相同、互為子目錄都算重疊）。
# 錯誤訊息裡印的是使用者看得懂的原始 candidate/skills_src（保留原始大小寫），但
# 實際比對一律透過 to_compare_key() 取得的 key 進行，這樣才能在 is_msys=1 時正確
# 忽略大小寫，同時不影響訊息可讀性。
check_target_boundaries() {
  local candidate="$1"
  # 去掉候選路徑尾端的斜線，方便跟下面的 drive-root pattern（/c、/d，不帶尾端
  # 斜線）比較；skills_src、resolved_root 等其他候選值本身不帶尾端斜線，用同一種
  # 去尾斜線後的形狀比較才不會漏判。
  local candidate_trimmed="${candidate%/}"
  local candidate_key skills_src_key
  candidate_key="$(to_compare_key "${candidate_trimmed}")"
  skills_src_key="$(to_compare_key "${skills_src}")"

  if [ -z "${candidate}" ] || [ "${candidate}" = "/" ]; then
    echo "錯誤: 目標技能根目錄解析後不可為根目錄 '${candidate}'，拒絕安裝以避免刪除根目錄下的內容" >&2
    return 1
  fi

  # bare drive root（/c、/d 等）只在確認執行環境是 MSYS/Cygwin 時才有意義——這是
  # NTFS 磁碟機根目錄的 MSYS 表示法，在真正的 POSIX 檔案系統上，一個字面上長得
  # 像 "/c" 的路徑就只是一個普通目錄，不該被當成危險根目錄拒絕。
  if [ "${is_msys}" -eq 1 ] && [[ "${candidate_key}" =~ ^/[a-z]$ ]]; then
    echo "錯誤: 目標技能根目錄解析後是 Windows drive root '${candidate}'，拒絕安裝以避免污染整個磁碟機" >&2
    return 1
  fi

  case "${candidate_key}/" in
    "${skills_src_key}/")
      echo "錯誤: 目標技能根目錄 '${candidate}' 與本 repo 的技能來源目錄 '${skills_src}' 相同，拒絕安裝" >&2
      return 1
      ;;
    "${skills_src_key}/"*)
      echo "錯誤: 目標技能根目錄 '${candidate}' 位於本 repo 的技能來源目錄 '${skills_src}' 之下，拒絕安裝" >&2
      return 1
      ;;
  esac
  case "${skills_src_key}/" in
    "${candidate_key}/"*)
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

# mkdir/cd 一律用上面已經正規化、驗證過的絕對路徑 hypothetical_root，並加上 `--`
# 明確終止選項解析——不要再把使用者原始輸入的 target_root 字串直接傳給 mkdir/cd。
# 實測重現過用 target_root 的具體危害：(a) target_root="-" 時，`cd -P "${target_root}"`
# 沒有 `--` 會被 Bash 當成特殊語法 `cd -`，不會 cd 進剛用 mkdir 建出來的 "-" 目錄，
# 而是跳到 $OLDPWD，還把 `cd -` 印出的新目錄那行一併被 command substitution 吃進
# resolved_root，讓它變成無意義的兩行字串；(b) target_root 是 Windows
# drive-relative 路徑（如 "C:foo"）時，`realpath -m` 把它正規化成 drive-絕對路徑
# 去做安全檢查，但 mkdir/cd 收到的原始字串卻被當成 CWD-relative 的普通檔名，兩者
# 對不上，等於安全檢查驗證的位置跟實際動作的位置是兩回事（另外已在上面用明確拒絕
# 這類輸入的方式處理，這裡的 `--` 是同一類「原始字串繞過正規化」問題的通用防線，
# 不只是為了那一個案例）。改用 hypothetical_root 之後，mkdir/cd 動作的位置保證
# 跟已經驗證過的位置完全一致，不會有另一個字串解讀方式偷偷生效的空間。
mkdir -p -- "${hypothetical_root}"
resolved_root="$(to_msys_form "$(cd -P -- "${hypothetical_root}" && pwd -P)")"

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
