#!/usr/bin/env node
/**
 * 财小全 · AI 财务中枢 —— 零依赖冒烟脚本
 * 用法: node tests/smoke_test.js [htmlPath]
 * 退出码: 0 全部通过; 1 存在失败
 */
"use strict";

const fs = require("fs");
const path = require("path");

const target = process.argv[2] || path.join(__dirname, "..", "src", "财小全-比赛修正版_修复版.html");
if (!fs.existsSync(target)) {
  console.error("找不到目标文件: " + target);
  process.exit(1);
}
const html = fs.readFileSync(target, "utf8");

let pass = 0;
const failures = [];

function check(name, ok, detail) {
  if (ok) {
    pass++;
    console.log("  PASS  " + name + (detail ? "  (" + detail + ")" : ""));
  } else {
    failures.push(name + (detail ? "  -> " + detail : ""));
    console.log("  FAIL  " + name + (detail ? "  (" + detail + ")" : ""));
  }
}

function count(re) {
  const m = html.match(re);
  return m ? m.length : 0;
}

console.log("目标文件: " + target);
console.log("大小: " + (Buffer.byteLength(html, "utf8") / 1024).toFixed(1) + " KB\n");

/* 1. 内联脚本语法 */
console.log("[1] 内联 JavaScript 语法");
const scripts = [];
const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
let m;
while ((m = re.exec(html)) !== null) {
  if (m[1].trim()) scripts.push(m[1]);
}
check("存在内联脚本", scripts.length > 0, scripts.length + " 段");
let syntaxOk = true;
let syntaxMsg = "";
scripts.forEach(function (code, i) {
  try {
    new Function(code);
  } catch (e) {
    syntaxOk = false;
    syntaxMsg = "第 " + (i + 1) + " 段: " + e.message;
  }
});
check("语法解析通过", syntaxOk, syntaxMsg || scripts.length + " 段全部可解析");

/* 2. 必需函数 */
console.log("\n[2] 必需函数");
const required = [
  "cxqRoute", "acctKey", "setAccount", "hasPerm", "launchSkill",
  "logAudit", "cxqHash", "verifyAuditChain", "exportAuditReport",
  "cxqDetectInjection", "cxqDetectPhishing", "cxqDetectWrite", "cxqMaskSensitive", "cxqCsvCell",
  "agentIdentity", "agentDataContext", "cxqChatDirect", "askAgent", "cxqOfflineAnswer", "llmConfig",
  "merge", "txnMonth", "txnYear", "cxqFundPlan", "simState", "saveSimPlan"
];
const missingFn = required.filter(function (fn) {
  return !new RegExp("function\\s+" + fn + "\\s*\\(").test(html);
});
check("26 个关键函数齐全", missingFn.length === 0, missingFn.join(", "));

/* 3. 存储键 */
console.log("\n[3] 存储键");
const keys = [
  "cxf-acct", "cxf-txns", "cxf-audit", "cxf-sched", "cxf-split", "cxf-loan-plans",
  "cxf-drafts", "cxf-llm", "cxf-llm-key", "cxf-sugg-state", "cxf-shop-idx", "cxf-hero-seen"
];
const missingKey = keys.filter(function (k) {
  return html.indexOf(k) === -1;
});
check("12 个存储键齐全", missingKey.length === 0, missingKey.join(", "));

/* 4. 静态 id 唯一性 */
console.log("\n[4] 静态 id 唯一性");
const idRe = /\sid="([A-Za-z0-9_\-]+)"/g;
const ids = [];
let im;
while ((im = idRe.exec(html)) !== null) ids.push(im[1]);
const dup = ids.filter(function (v, i) { return ids.indexOf(v) !== i; });
const dupUnique = Array.from(new Set(dup));
check("id 无重复", dupUnique.length === 0, "共 " + ids.length + " 个，重复 " + dupUnique.length + " 个" + (dupUnique.length ? ": " + dupUnique.join(", ") : ""));

/* 5. 外部依赖 */
console.log("\n[5] 外部依赖");
const extSrc = count(/<script[^>]*\bsrc\s*=\s*["']https?:/gi);
const extLink = count(/<link[^>]*\bhref\s*=\s*["']https?:/gi);
const extImg = count(/<img[^>]*\bsrc\s*=\s*["']https?:/gi);
check("无外部脚本", extSrc === 0, "外链 script " + extSrc + " 处");
check("无外部样式/字体", extLink === 0, "外链 link " + extLink + " 处");
check("无外部图片", extImg === 0, "外链 img " + extImg + " 处");

/* 6. 关键数值与文案 */
console.log("\n[6] 关键数值");
check("税务演示销售额 342500", html.indexOf("342500") > -1 || html.indexOf("342,500") > -1);
check("税额 3425", html.indexOf("3425") > -1 || html.indexOf("3,425") > -1);
check("DTI 口径存在", html.indexOf("DTI") > -1);
check("96110 反诈指引", html.indexOf("96110") > -1);
check("申报边界说明", html.indexOf("替代申报") > -1 || html.indexOf("不可直接替代") > -1);

/* 7. 安全实现点 */
console.log("\n[7] 安全实现点");
check("CSV 公式注入防护", /\[\s*=\+@\s*\]/.test(html) && /s\s*=\s*"'"\s*\+\s*s/.test(html), "= + @ - 前缀加单引号");
check("上下文脱敏调用", /cxqMaskSensitive\s*\(/.test(html));
check("写操作二次确认", /cxqProposeWrite/.test(html) || /cxqConfirmWrite/.test(html));
check("审计链初始化校验", /verifyAuditChain\s*\(/.test(html));

console.log("\n----------------------------------------");
console.log("通过 " + pass + " 项，失败 " + failures.length + " 项");
if (failures.length) {
  console.log("失败项:");
  failures.forEach(function (f) { console.log("  - " + f); });
  process.exit(1);
}
console.log("结果: 全部通过");
