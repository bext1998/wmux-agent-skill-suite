#!/usr/bin/env bash
# 驗證通用安裝腳本會拒絕危險的目標路徑（空字串、根目錄、與來源目錄重疊——含
# symlink 情況），且在拒絕前不會建立/污染/刪除任何東西。
#
# 已知限制：部分情境（情境 6、7）用 `ln -s` 建立目錄 symlink 來測試 symlink 解析，
# 在某些 Windows/Git Bash 環境下，`ln -s`／`readlink` 對目錄可能不會表現成真正的
# POSIX symlink（例如退化成 junction，`readlink` 讀不到目標），導致這兩個情境在
# 該類本機環境下不足以真正驗證 symlink 解析邏輯本身，只能確認「即使 symlink 沒被
# 正確辨識，行為仍然安全」。這兩個情境設計上是為了在提供真正 POSIX symlink 語意的
# 環境（例如 CI 的 ubuntu-latest）下驗證 scripts/install.sh 對 symlink 的解析。
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

# 跟 scripts/install.sh 用同一種偵測方式（uname -s，比 uname -o 更可攜——macOS
# 沒有 -o），確保這裡「該不該跑 MSYS 專屬情境」的判斷跟被測試對象本身的判斷邏輯
# 一致，不會出現測試環境判斷跟腳本內部判斷分歧、各測各的的情況。
is_msys=0
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) is_msys=1 ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

# 情境 1：空字串 target，必須被明確拒絕（非零 exit code），且不能建立任何東西。
if output="$(bash "${repo_root}/scripts/install.sh" "" 2>&1)"; then
  echo "FAIL: install.sh 對空字串 target 應該失敗，但卻成功了"
  fail=1
else
  if ! echo "${output}" | grep -q "不可為空字串"; then
    echo "FAIL: install.sh 對空字串 target 的錯誤訊息不符預期"
    echo "  實際輸出: ${output}"
    fail=1
  fi
fi

# 情境 2：target 解析後為根目錄 '/'，必須被明確拒絕，不能對 /wmux-* 執行 rm -rf。
#
# 執行環境可能原本就已經有 /wmux-best-practice 或 /wmux-coordinator（跟本 repo 無關
# 的既有內容），所以不能單純斷言「執行後不存在」——要先記錄執行前的狀態（存在與否，
# 以及存在時的內容指紋），執行後比對狀態完全沒變，而不是誤把「本來就存在」當成失敗。
fingerprint() {
  local path="$1"
  if [ -e "${path}" ]; then
    find "${path}" -type f -exec sha256sum {} \; 2>/dev/null | sort
  else
    echo "<not-present>"
  fi
}

before_best_practice="$(fingerprint /wmux-best-practice)"
before_coordinator="$(fingerprint /wmux-coordinator)"

if output="$(bash "${repo_root}/scripts/install.sh" "/" 2>&1)"; then
  echo "FAIL: install.sh 對根目錄 target 應該失敗，但卻成功了"
  fail=1
else
  if ! echo "${output}" | grep -q "根目錄"; then
    echo "FAIL: install.sh 對根目錄 target 的錯誤訊息不符預期"
    echo "  實際輸出: ${output}"
    fail=1
  fi
fi

after_best_practice="$(fingerprint /wmux-best-practice)"
after_coordinator="$(fingerprint /wmux-coordinator)"

if [ "${before_best_practice}" != "${after_best_practice}" ]; then
  echo "FAIL: install.sh 對根目錄 target 的防護失效，/wmux-best-practice 的狀態在執行前後改變了"
  fail=1
fi
if [ "${before_coordinator}" != "${after_coordinator}" ]; then
  echo "FAIL: install.sh 對根目錄 target 的防護失效，/wmux-coordinator 的狀態在執行前後改變了"
  fail=1
fi

# 情境 3-6 共用一份 repo 的隔離副本，避免互相汙染彼此的檢查結果。
isolated_repo="${tmp_dir}/isolated-repo"
cp -r "${repo_root}" "${isolated_repo}"
rm -rf "${isolated_repo}/node_modules"

assert_sources_intact() {
  local label="$1"
  for skill in wmux-best-practice wmux-coordinator; do
    if [ ! -f "${isolated_repo}/skills/${skill}/SKILL.md" ]; then
      echo "FAIL: ${label} 的防護失效，${skill}/SKILL.md 來源被刪掉了"
      fail=1
    fi
  done
}

assert_rejected_with() {
  local label="$1" target="$2" expect_grep="$3"
  if output="$(bash "${isolated_repo}/scripts/install.sh" "${target}" 2>&1)"; then
    echo "FAIL: ${label} 應該失敗，但卻成功了"
    fail=1
    return
  fi
  if ! echo "${output}" | grep -q "${expect_grep}"; then
    echo "FAIL: ${label} 的錯誤訊息不符預期"
    echo "  實際輸出: ${output}"
    fail=1
  fi
}

# 情境 3：target 與來源 skills/ 完全相同（例如使用者不小心把 target 指向 repo
# 自己的 skills/）。在隔離副本上重現過：install.sh 會先 rm -rf
# skills/wmux-best-practice（刪掉來源），再因為來源已被刪除而 cp 失敗，造成技能
# 來源目錄損毀。
assert_rejected_with "install.sh 對『target 與來源 skills/ 相同』" \
  "${isolated_repo}/skills" "來源目錄"
assert_sources_intact "『target 與來源 skills/ 相同』"

# 情境 4：target 是 skills/ 底下一個原本不存在的子目錄（互為父子關係的其中一種：
# 來源是目標的父目錄）。這個情境同時驗證「拒絕發生在建立/汙染路徑之前」——修法前
# 的 bug 是 mkdir -p 發生在重疊檢查之前，會先把這個不存在的子目錄建到來源目錄
# 底下，檢查沒過才拒絕，為時已晚。
new_subdir="${isolated_repo}/skills/newsub-does-not-exist"
assert_rejected_with "install.sh 對『target 是來源 skills/ 底下不存在的子目錄』" \
  "${new_subdir}" "來源目錄"
if [ -e "${new_subdir}" ]; then
  echo "FAIL: install.sh 在拒絕『target 是來源 skills/ 底下不存在的子目錄』之前，就已經把 '${new_subdir}' 建立出來了（污染來源目錄）"
  fail=1
fi
assert_sources_intact "『target 是來源 skills/ 底下不存在的子目錄』"

# 情境 5：target 是來源 skills/ 的父目錄（互為父子關係的另一種：目標是來源的
# 父目錄），例如使用者把 target 設成 repo 根目錄本身。
assert_rejected_with "install.sh 對『target 是來源 skills/ 的父目錄』" \
  "${isolated_repo}" "來源目錄"
assert_sources_intact "『target 是來源 skills/ 的父目錄』"

# 情境 6：target 是指向來源 skills/ 的 symlink（而不是直接寫來源路徑本身）。
# 見檔案開頭「已知限制」：在部分本機環境下這個 symlink 可能不會被辨識成真正的
# POSIX symlink，但無論是否被正確辨識，行為都必須是安全的（要嘛正確識破 symlink
# 而拒絕，要嘛至少不會把來源刪壞）。
target_symlink="${tmp_dir}/target-symlink-to-skills"
ln -s "${isolated_repo}/skills" "${target_symlink}" 2>/dev/null
if [ -L "${target_symlink}" ]; then
  if output="$(bash "${isolated_repo}/scripts/install.sh" "${target_symlink}" 2>&1)"; then
    echo "FAIL: install.sh 對『target 是指向來源 skills/ 的 symlink』應該失敗，但卻成功了"
    fail=1
  else
    if ! echo "${output}" | grep -q "來源目錄"; then
      echo "FAIL: install.sh 對『target 是指向來源 skills/ 的 symlink』的錯誤訊息不符預期"
      echo "  實際輸出: ${output}"
      fail=1
    fi
  fi
  assert_sources_intact "『target 是指向來源 skills/ 的 symlink』"
else
  echo "SKIP: 目前環境無法建立目錄 symlink，跳過情境 6（見檔案開頭「已知限制」）"
fi

# 情境 7：skills/ 本身是 symlink，指向 repo 之外的真實目錄；target 直接寫真實目錄
# 的路徑（不透過 skills/ 這個 symlink）。這是修法前 issue 2 的具體 bug：舊版只解析
# repo_root，没有對 skills/ 本身再做一次 cd -P/pwd -P，若 skills/ 本身是 symlink，
# skills_src 會停留在 symlink 路徑字串，跟這裡「直接寫真實目錄路徑」的 target 字串
# 比對不出重疊，漏判。
external_skills_dir="${tmp_dir}/external-skills-dir"
mkdir -p "${external_skills_dir}"
cp -r "${isolated_repo}/skills/wmux-best-practice" "${external_skills_dir}/"
cp -r "${isolated_repo}/skills/wmux-coordinator" "${external_skills_dir}/"
rm -rf "${isolated_repo}/skills"
ln -s "${external_skills_dir}" "${isolated_repo}/skills" 2>/dev/null
if [ -L "${isolated_repo}/skills" ]; then
  if output="$(bash "${isolated_repo}/scripts/install.sh" "${external_skills_dir}" 2>&1)"; then
    echo "FAIL: install.sh 對『skills/ 本身是 symlink，target 直接寫真實來源目錄』應該失敗，但卻成功了"
    fail=1
  else
    if ! echo "${output}" | grep -q "來源目錄"; then
      echo "FAIL: install.sh 對『skills/ 本身是 symlink，target 直接寫真實來源目錄』的錯誤訊息不符預期"
      echo "  實際輸出: ${output}"
      fail=1
    fi
  fi
  for skill in wmux-best-practice wmux-coordinator; do
    if [ ! -f "${external_skills_dir}/${skill}/SKILL.md" ]; then
      echo "FAIL: install.sh 對『skills/ 本身是 symlink，target 直接寫真實來源目錄』的防護失效，${skill}/SKILL.md 真實來源被刪掉了"
      fail=1
    fi
  done
else
  echo "SKIP: 目前環境無法建立目錄 symlink，跳過情境 7（見檔案開頭「已知限制」）"
fi

# 情境 8：target 用 Windows 原生 drive-letter 形式（D:/...）指向來源 skills/ 底下
# 一個原本不存在的子目錄——跟情境 4 測的是同一個危險落點，但用不同的路徑「表示法」
# 呈現。只在 Windows/Git Bash（MSYS）環境下才有意義：這是 `realpath -m` 對尚未存在
# 的路徑只做純文字正規化、不會把 drive-letter 前綴轉成 /d/... 形式，導致跟
# `cd -P/pwd -P` 產生的 skills_src 字串對不上、漏判重疊的具體情境（修法前：
# mkdir -p 會先把子目錄建到來源目錄裡面，才在事後檢查被抓到）。
if [ "${is_msys}" -eq 1 ]; then
  native_new_subdir_msys="${isolated_repo}/skills/newsub-native-drive-form"
  # 把隔離副本的 MSYS 路徑（/d/foo/...）轉成 Windows 原生 drive-letter 形式
  # （D:/foo/...），模擬呼叫端直接貼上 Windows 原生路徑當 target 的情境。
  native_new_subdir="$(printf '%s' "${native_new_subdir_msys}" | sed -E 's#^/([A-Za-z])/#\1:/#')"
  assert_rejected_with "install.sh 對『target 用 Windows 原生 drive-letter 形式指向來源 skills/ 底下不存在的子目錄』" \
    "${native_new_subdir}" "來源目錄"
  if [ -e "${native_new_subdir_msys}" ]; then
    echo "FAIL: install.sh 在拒絕『target 用 Windows 原生 drive-letter 形式指向來源 skills/ 底下不存在的子目錄』之前，就已經把 '${native_new_subdir_msys}' 建立出來了（污染來源目錄——realpath -m 與 cd -P/pwd -P 正規化結果不一致造成漏判）"
    fail=1
  fi
  assert_sources_intact "『target 用 Windows 原生 drive-letter 形式指向來源 skills/ 底下不存在的子目錄』"
else
  echo "SKIP: 目前環境不是 Windows/Git Bash（MSYS），跳過情境 8（drive-letter 正規化只在該環境下有意義）"
fi

# 情境 9：target 是 Windows drive root 本身（D:/、D:\、C:/ 等），必須被明確拒絕，
# 不能對整個磁碟機根目錄下寫入 wmux-best-practice/wmux-coordinator。只在
# Windows/Git Bash（MSYS）環境下有意義——非 Windows 環境沒有 drive-letter 路徑，
# 這幾個字串會被當成一般的（多半不存在或無寫入權限的）POSIX 路徑處理，不構成同一種
# 風險。
if [ "${is_msys}" -eq 1 ]; then
  for drive_root_form in "D:/" 'D:\' "C:/"; do
    if output="$(bash "${isolated_repo}/scripts/install.sh" "${drive_root_form}" 2>&1)"; then
      echo "FAIL: install.sh 對 Windows drive root target '${drive_root_form}' 應該失敗，但卻成功了"
      fail=1
    else
      if ! echo "${output}" | grep -q "drive root"; then
        echo "FAIL: install.sh 對 Windows drive root target '${drive_root_form}' 的錯誤訊息不符預期"
        echo "  實際輸出: ${output}"
        fail=1
      fi
    fi
  done
  assert_sources_intact "『target 是 Windows drive root』"
else
  echo "SKIP: 目前環境不是 Windows/Git Bash（MSYS），跳過情境 9（drive root 拒絕只在該環境下有意義）"
fi

# 情境 10：target 用跟 skills_src 大小寫不同（但實際上是磁碟上同一個目錄）的形式，
# 指向來源 skills/ 底下一個原本不存在的子目錄。只在 Windows/Git Bash（MSYS）環境下
# 有意義——NTFS 預設不分大小寫但保留大小寫，這裡是「realpath -m 與 cd -P/pwd -P 的
# drive-letter 已經正規化一致，但路徑其餘部分大小寫仍不同」這個殘餘風險：本地實測
# 過（見 scripts/install.sh 的註解），修法前這種大小寫不同的路徑會被誤判成跟
# skills_src 不重疊而放行，讓 mkdir -p 把新目錄建到磁碟上同一個實際目錄（技能來源
# 目錄）底下。
if [ "${is_msys}" -eq 1 ]; then
  case_mismatch_subdir_lower="${isolated_repo}/skills/newsub-case-mismatch"
  # 把整個路徑轉大寫，模擬呼叫端用跟磁碟上實際大小寫不同的形式指向同一個目錄。
  case_mismatch_subdir_upper="$(printf '%s' "${case_mismatch_subdir_lower}" | tr '[:lower:]' '[:upper:]')"
  assert_rejected_with "install.sh 對『target 與來源 skills/ 大小寫不同但磁碟上是同一個目錄』" \
    "${case_mismatch_subdir_upper}" "來源目錄"
  if [ -e "${case_mismatch_subdir_lower}" ]; then
    echo "FAIL: install.sh 在拒絕『target 與來源 skills/ 大小寫不同但磁碟上是同一個目錄』之前，就已經把 '${case_mismatch_subdir_lower}' 建立出來了（污染來源目錄——NTFS 不分大小寫但路徑比對區分大小寫造成漏判）"
    fail=1
  fi
  assert_sources_intact "『target 與來源 skills/ 大小寫不同但磁碟上是同一個目錄』"
else
  echo "SKIP: 目前環境不是 Windows/Git Bash（MSYS），跳過情境 10（NTFS 大小寫不敏感只在該環境下有意義）"
fi

# 情境 11：反向情境——只在「非」MSYS（真正的 POSIX 檔案系統，大小寫不同就是不同
# 目錄）環境下有意義。驗證兩件事，避免情境 8-10 的 MSYS 專屬修正對 Linux/macOS 造成
# 誤傷：(a) 一個字面上長得像 Windows drive root 的 bare 單字母絕對路徑（例如 "/x"）
# 不會被誤判成 drive root 而拒絕——install.sh 可能因為權限或其他原因失敗，但錯誤
# 訊息不能是「drive root」；(b) target 跟 skills_src 只有大小寫不同、實際上是磁碟上
# 兩個不同的目錄時，不能被誤判成重疊而拒絕——必須正常安裝成功。
if [ "${is_msys}" -ne 1 ]; then
  bare_single_letter_output="$(bash "${isolated_repo}/scripts/install.sh" "/x" 2>&1)" || true
  if printf '%s' "${bare_single_letter_output}" | grep -qi "drive root"; then
    echo "FAIL: 非 MSYS 環境下，install.sh 把字面上的 bare 單字母路徑 '/x' 誤判成 Windows drive root 而拒絕"
    echo "  實際輸出: ${bare_single_letter_output}"
    fail=1
  fi

  # 只把最後一段元件（"skills" -> "SKILLS"）轉大寫，父目錄（isolated_repo，已經
  # 存在且可寫）維持原樣——不能對整個絕對路徑做 tr，那樣連 /tmp 這種系統層級、
  # 不歸這個測試管、通常也沒有建立權限的路徑前綴都會被轉成 /TMP，導致 mkdir 因為
  # 權限不足而失敗，跟「大小寫重疊誤判」這個真正要測的東西無關（已在 CI 的
  # ubuntu-latest 上實際踩到這個問題：mkdir 因為 /TMP 沒有寫入權限而失敗，被誤判
  # 成 install.sh 的邊界檢查有 bug）。
  case_diff_target="$(dirname "${isolated_repo}/skills")/$(basename "${isolated_repo}/skills" | tr '[:lower:]' '[:upper:]')"
  if [ "${case_diff_target}" != "${isolated_repo}/skills" ]; then
    if ! case_diff_output="$(bash "${isolated_repo}/scripts/install.sh" "${case_diff_target}" 2>&1)"; then
      echo "FAIL: 非 MSYS（大小寫敏感）環境下，install.sh 把跟 skills_src 只有大小寫不同、實際是不同目錄的 target 誤判成重疊而拒絕"
      echo "  實際輸出: ${case_diff_output}"
      fail=1
    fi
    assert_sources_intact "『非 MSYS 環境下 target 與來源 skills/ 只有大小寫不同（不同目錄）』"
    rm -rf "${case_diff_target}"
  fi
else
  echo "SKIP: 目前環境是 Windows/Git Bash（MSYS），跳過情境 11（驗證非 MSYS 平台不被 MSYS 專屬修正誤傷，只在非 MSYS 平台下有意義）"
fi

# 情境 12（PR34-CX-5 Finding 1，Major）：target 是單一 "-"。realpath -m 對此的
# 正規化結果是 CWD 底下一個叫 "-" 的路徑（例如 <cwd>/-），會通過邊界檢查；但修法前
# 的 mkdir -p 與第二次 cd -P 直接把 target_root 原始字串傳給指令，沒有用 `--`、也
# 沒有改用已正規化的絕對路徑。`cd -P "-"`（沒有 --）會被 Bash 當成特殊語法
# `cd -`——不會 cd 進剛剛用 mkdir 建出來的 "-" 目錄，而是跳到 $OLDPWD，且 `cd -`
# 印出的新目錄那行也一併被 command substitution 吃進去，讓 resolved_root 變成兩行
# 字串（實測：`$'/some/dir\n/some/dir'` 這種形狀）。淨效果：mkdir -p 已經在呼叫端
# 的工作目錄下建立了一個叫 "-" 的目錄，但後續驗證與安裝卻對著一個完全不同、且格式
# 已損毀的路徑繼續動作，最終安裝失敗——這是「先建立/污染，檢查沒過才發現為時已晚」
# 的具體案例，這次污染的是呼叫端的 CWD，不是 skills_src。這個問題是一般 Bash 行為
# （`cd -` 特例），不限 MSYS，不用 is_msys gate。
#
# 正確行為只有兩種：(a) 乾淨拒絕，完全不在 CWD 建立任何東西；(b) 正確辨識、完整
# 安裝成功，"-" 目錄裡確實有完整的兩個技能。不允許「建立了一個空的/不完整的
# "-"，但腳本卻回報失敗」這種半成品狀態——這正是 resolved_root 被 cd -P 特例污染
# 後的實際後果，也是本情境要抓的紅燈。
dash_target_cwd="${tmp_dir}/dash-target-cwd"
mkdir -p "${dash_target_cwd}"
if [ -e "${dash_target_cwd}/-" ]; then
  echo "FAIL: 情境 12 前置狀態異常——'${dash_target_cwd}/-' 執行前就已存在"
  fail=1
else
  dash_output="$(cd "${dash_target_cwd}" && bash "${isolated_repo}/scripts/install.sh" "-" 2>&1)"
  dash_exit=$?
  if [ -e "${dash_target_cwd}/-" ]; then
    # 建立了東西：必須是完整、正確安裝好的兩個技能，不能是空的/半成品。
    if [ ! -f "${dash_target_cwd}/-/wmux-best-practice/SKILL.md" ] || [ ! -f "${dash_target_cwd}/-/wmux-coordinator/SKILL.md" ]; then
      echo "FAIL: install.sh 對 target='-' 建立了 '${dash_target_cwd}/-'，但裡面沒有完整安裝兩個技能（半成品/空目錄）——exit code ${dash_exit}"
      echo "  實際輸出: ${dash_output}"
      fail=1
    elif [ "${dash_exit}" -ne 0 ]; then
      echo "FAIL: install.sh 對 target='-' 明明已經完整安裝好兩個技能，卻仍回報失敗（exit code ${dash_exit}）——結果與回報的成功/失敗狀態矛盾"
      echo "  實際輸出: ${dash_output}"
      fail=1
    fi
  else
    # 沒建立任何東西：必須是明確、非零的拒絕，不能是「什麼都沒做卻回報成功」。
    if [ "${dash_exit}" -eq 0 ]; then
      echo "FAIL: install.sh 對 target='-' 回報成功，但 '${dash_target_cwd}/-' 並不存在——回報的成功狀態與實際結果不符"
      echo "  實際輸出: ${dash_output}"
      fail=1
    fi
  fi
fi
assert_sources_intact "『target 是單一 "-"』"
rm -rf "${dash_target_cwd}"

# 情境 13（PR34-CX-5 Finding 2，Moderate）：target 是 Windows drive-relative 路徑
# （drive letter 後面接的不是 / 或 \，例如 "C:foo"）。只在 MSYS 有意義——這是
# Windows 路徑語意裡「相對於 C: 磁碟機當下工作目錄」的寫法，跟 "C:/foo"（drive
# 絕對路徑）語意不同。修法前 `to_msys_form` 的正則把 "C:foo" 的斜線視為可選，
# 誤把它正規化成 "/c/foo"（drive-絕對形式）去做邊界檢查；但真正呼叫 mkdir/cd 的
# 卻是原始字串 "C:foo"——MSYS 的 mkdir/cd 不理解 Windows drive 語意，把它當成一個
# CWD-relative、字面上含冒號的普通檔名。也就是說：邊界檢查驗證的是「/c/foo」這個
# 位置是否安全，但實際 mkdir -p 動作的卻是完全不同的「CWD 底下一個叫 C:foo 的
# 目錄」——兩者對不上，等於邊界檢查形同虛設。
#
# 本情境在 CWD 就是技能來源目錄本身（isolated_repo/skills）的情況下重現：實測過
# 修法前的行為——第一次（mkdir 前）邊界檢查用 "/c/..." 這個跟 skills_src 完全不
# 重疊的位置通過，讓 mkdir -p 真的在 skills/ 底下建出一個字面上叫
# "C:pollute-probe" 的目錄，污染了技能來源目錄本身；雖然第二次（mkdir 後）用
# cd -P 重新解析出的路徑最終還是抓到重疊而讓整體安裝失敗，但污染已經發生，不能
# 只看最終 exit code 判斷安全。正確修法必須在任何 mkdir 發生前就直接拒絕這種
# drive-relative 輸入，不去猜測它實際上對應磁碟上的哪個目錄。
if [ "${is_msys}" -eq 1 ]; then
  drive_relative_pollution_target="C:pollute-probe-$$"
  before_skills_listing="$(ls -A "${isolated_repo}/skills" | sort)"
  drive_relative_output="$(cd "${isolated_repo}/skills" && bash "${isolated_repo}/scripts/install.sh" "${drive_relative_pollution_target}" 2>&1)"
  drive_relative_exit=$?
  after_skills_listing="$(ls -A "${isolated_repo}/skills" | sort)"
  if [ "${drive_relative_exit}" -eq 0 ]; then
    echo "FAIL: install.sh 對 Windows drive-relative target '${drive_relative_pollution_target}' 應該失敗，但卻成功了"
    echo "  實際輸出: ${drive_relative_output}"
    fail=1
  fi
  if [ "${before_skills_listing}" != "${after_skills_listing}" ]; then
    echo "FAIL: install.sh 在拒絕 Windows drive-relative target '${drive_relative_pollution_target}' 之前，就已經污染了技能來源目錄本身（skills/ 底下多出非預期項目）——邊界檢查驗證的位置跟 mkdir 實際動作的位置對不上"
    echo "  執行前: ${before_skills_listing}"
    echo "  執行後: ${after_skills_listing}"
    echo "  實際輸出: ${drive_relative_output}"
    fail=1
    # 清掉污染，避免影響本檔案後續情境或殘留在 isolated_repo。
    rm -rf "${isolated_repo}/skills/${drive_relative_pollution_target}"
  fi
  assert_sources_intact "『target 是 Windows drive-relative 路徑』"

  # 情境 14：確認修正沒有連帶弱化既有保護——"C:"（drive letter 後面直接結尾，沒有
  # 任何路徑內容）本來就該被既有的 bare drive-root 檢查擋下（正規化後就是 "/c"），
  # 不屬於這次新增的 drive-relative 拒絕範圍，必須繼續維持安全拒絕。
  if output="$(bash "${isolated_repo}/scripts/install.sh" "C:" 2>&1)"; then
    echo "FAIL: install.sh 對 target='C:' 應該失敗，但卻成功了"
    fail=1
  else
    if ! echo "${output}" | grep -qi "drive root"; then
      echo "FAIL: install.sh 對 target='C:' 的錯誤訊息不符預期（應仍歸類為 drive root，不應變成別的分類或被放行）"
      echo "  實際輸出: ${output}"
      fail=1
    fi
  fi
  assert_sources_intact "『target 是單獨的 C:』"
else
  echo "SKIP: 目前環境不是 Windows/Git Bash（MSYS），跳過情境 13-14（Windows drive-relative 路徑語意只在該環境下有意義）"
fi

# 情境 15：反向情境——只在「非」MSYS 環境下有意義。驗證情境 13 新增的
# drive-relative 拒絕沒有誤傷非 Windows 平台：一個字面上長得像 Windows
# drive-relative 路徑的字串（例如 "C:foo"）在真正的 POSIX 檔案系統上就只是一個
# 含冒號的普通相對檔名，不該被誤判拒絕。
#
# 修正（PR34-CX-6，Codex 獨立審查發現）：先前用 `|| true` 吞掉 exit code、只檢查
# 輸出文字沒有出現 drive-relative/drive root 關鍵字，這樣如果 install.sh 因為
# 其他無關原因失敗（例如某個非預期的 bug），只要錯誤訊息剛好沒提到這兩個關鍵字，
# 測試依然會回報綠燈——沒有真正驗證「install.sh 有沒有成功完成安裝」這件事本身。
# 改為明確要求 exit code 必須是 0，且目標目錄底下兩個技能的 SKILL.md 都要實際
# 存在，才算通過；失敗時完整印出實際輸出，不吞掉任何錯誤細節。
if [ "${is_msys}" -ne 1 ]; then
  literal_colon_target="${tmp_dir}/literal-colon-target"
  mkdir -p "${literal_colon_target}"
  literal_colon_output="$(cd "${literal_colon_target}" && bash "${isolated_repo}/scripts/install.sh" "C:foo-literal" 2>&1)"
  literal_colon_exit=$?
  if [ "${literal_colon_exit}" -ne 0 ]; then
    echo "FAIL: 非 MSYS 環境下，install.sh 對字面上的 'C:foo-literal' 應該成功安裝，卻回報失敗（exit code ${literal_colon_exit}）"
    echo "  實際輸出: ${literal_colon_output}"
    fail=1
  elif [ ! -f "${literal_colon_target}/C:foo-literal/wmux-best-practice/SKILL.md" ] || [ ! -f "${literal_colon_target}/C:foo-literal/wmux-coordinator/SKILL.md" ]; then
    echo "FAIL: 非 MSYS 環境下，install.sh 對字面上的 'C:foo-literal' 回報成功（exit 0），但目標目錄底下沒有完整安裝兩個技能的 SKILL.md"
    echo "  實際輸出: ${literal_colon_output}"
    fail=1
  fi
  assert_sources_intact "『非 MSYS 環境下 target 字面上長得像 drive-relative 路徑』"
  rm -rf "${literal_colon_target}"
else
  echo "SKIP: 目前環境是 Windows/Git Bash（MSYS），跳過情境 15（驗證非 MSYS 平台不被 drive-relative 拒絕誤傷，只在非 MSYS 平台下有意義）"
fi

if [ "${fail}" -eq 0 ]; then
  echo "PASS: 安裝腳本負向測試通過"
fi
exit "${fail}"
