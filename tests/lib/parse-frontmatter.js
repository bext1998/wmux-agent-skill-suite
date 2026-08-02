#!/usr/bin/env node
// 解析 SKILL.md 的 YAML frontmatter，使用真正合規的 YAML parser（js-yaml），
// 而不是只 grep name/description 字串，也不是自製、只支援子集的 parser。
//
// 依賴透過 package.json + package-lock.json 鎖定版本，CI 需先執行 `npm ci`
// 安裝依賴（見 .github/workflows/ci.yml）。
//
// 用法: node parse-frontmatter.js <path-to-SKILL.md> [field]
//
//   不帶 field：成功時把整個解析結果印成單行 JSON 到 stdout，格式為
//     {"name": "...", "descriptionOk": true|false}
//   field 為 "name"：成功時只印 name 欄位的值（不存在時為空字串）
//   field 為 "description-ok"：成功時只印 '1'（description 存在且為非空字串）或 '0'
//
// 不管哪種模式，輸出永遠保證只有一行、不含 CR/LF：name 欄位若含有 CR 或 LF
// （例如用 YAML 的 literal/folded block scalar 或跳脫字元塞進換行）一律視為不合法
// 而直接拒絕。這是刻意的邊界檢查——先前的實作單純把 name 印在 stdout 第一行、
// description 是否非空印在第二行，若 name 本身含換行，就能在第一行放進假的
// name、在第二行放進偽造的 '1'，讓呼叫端的行號解析被誤導成「驗證通過」。改成
// 「拒絕 name 含換行」加上「單行 JSON」雙重保險後，呼叫端不會再需要按行號解析，
// 也不會有藏在 name 裡的偽造行可以利用。
//
// 任何解析失敗（缺少 frontmatter 分隔線、YAML 語法錯誤、duplicate key、
// frontmatter 不是 mapping、name 含 CR/LF 等）都會以非零 exit code 結束，
// 並在 stderr 印出原因。

const fs = require("node:fs");
const yaml = require("js-yaml");

function fail(message) {
  process.stderr.write(message + "\n");
  process.exit(1);
}

// frontmatter 分隔線必須是「該行整行恰好是 ---，且完全不縮排」（column-zero），
// 不能用 trim() 之後比對——若用 trim()，YAML block scalar（`description: |`／`>`）
// 內部縮排的內容行剛好整行只有 "---" 時（合法的 YAML 內容，只是恰好長得像分隔
// 線），trim() 後一樣會等於 "---"，導致 extractFrontmatterText 把它誤判成
// frontmatter 結尾，提早截斷，吃掉分隔線之後、block scalar 裡原本還沒結束的內容，
// 且不會報錯——因為被截斷的殘骸往往仍是合法 YAML，只是語意錯誤（悄悄漏掉一段
// description）。真正的分隔線在慣例上一律頂格、整行只有三個 dash，不會有縮排；
// 用嚴格相等（不 trim）就能只匹配真正頂格的分隔線，跳過 block scalar 內縮排的同形字串。
function isDelimiterLine(line) {
  return line === "---";
}

function extractFrontmatterText(text) {
  const lines = text.split(/\r\n|\n/);
  if (lines.length === 0 || !isDelimiterLine(lines[0])) {
    throw new Error("第一行不是頂格的 '---'，frontmatter 缺失");
  }
  let endIndex = -1;
  for (let i = 1; i < lines.length; i++) {
    if (isDelimiterLine(lines[i])) {
      endIndex = i;
      break;
    }
  }
  if (endIndex === -1) {
    throw new Error("找不到頂格的 frontmatter 結尾 '---'");
  }
  return lines.slice(1, endIndex).join("\n");
}

function main() {
  const path = process.argv[2];
  const field = process.argv[3];
  if (!path) {
    process.stderr.write(
      "usage: parse-frontmatter.js <SKILL.md path> [name|description-ok]\n"
    );
    process.exit(2);
  }
  if (field !== undefined && field !== "name" && field !== "description-ok") {
    process.stderr.write(`未知的 field: ${JSON.stringify(field)}\n`);
    process.exit(2);
  }

  const text = fs.readFileSync(path, "utf8");

  let mapping;
  try {
    const fmText = extractFrontmatterText(text);
    // js-yaml 預設（`json: false`）就會在同一個 mapping 出現 duplicate key 時拋錯，
    // 不需要額外的自訂 loader。
    mapping = yaml.load(fmText);
  } catch (err) {
    fail(err.message);
    return;
  }

  // 不能只檢查 `typeof mapping === "object"`：js-yaml 的預設 schema 會把符合
  // ISO-8601 格式的純量（例如整份 frontmatter 內容只有一行 `2026-08-02`）用
  // 隱式 `!!timestamp` tag 解析成 JS `Date` 物件，而 `Date` 的 `typeof` 也是
  // `"object"`、也不是 array，會被舊版檢查誤判成「合法 mapping（只是剛好沒有
  // name/description 欄位）」而放行，實際上 frontmatter 頂層根本不是 mapping。
  // 用 `Object.prototype.toString` 分辨真正的 plain mapping（`[object Object]`）
  // 跟 `Date`/`RegExp` 等其他 js-yaml 可能解析出的物件型別（`[object Date]` 等）。
  const isPlainMapping =
    mapping !== null &&
    typeof mapping === "object" &&
    !Array.isArray(mapping) &&
    Object.prototype.toString.call(mapping) === "[object Object]";

  if (!isPlainMapping) {
    fail("frontmatter 內容不是合法的 YAML mapping");
    return;
  }

  const name = typeof mapping.name === "string" ? mapping.name : "";
  if (/[\r\n]/.test(name)) {
    fail(
      `name 欄位含有 CR/LF，拒絕：多行的 name 會讓依賴逐行輸出的呼叫端誤判 (${JSON.stringify(
        name
      )})`
    );
    return;
  }

  const descriptionOk =
    typeof mapping.description === "string" && mapping.description.trim() !== "";

  if (field === "name") {
    process.stdout.write(name + "\n");
    return;
  }
  if (field === "description-ok") {
    process.stdout.write((descriptionOk ? "1" : "0") + "\n");
    return;
  }

  process.stdout.write(JSON.stringify({ name, descriptionOk }) + "\n");
}

main();
