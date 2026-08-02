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

if [ "${fail}" -eq 0 ]; then
  echo "PASS: 安裝腳本負向測試通過"
fi
exit "${fail}"
