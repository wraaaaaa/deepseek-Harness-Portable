'use strict';
/**
 * 内核补丁应用脚本（可重复、幂等）。由 build.ps1 在内核复制后执行。
 *
 * 补丁清单：
 *  1. node-pty/lib/ia32-shim.js        —— 新增：ia32 无原生预编译时的纯 JS 垫片
 *  2. node-pty/lib/index.js            —— 插入 ia32 短路分流（3 行）
 *  3. dsh-sandbox-windows-acl/lib/types-*.js —— STARTUPINFOW/PROCESS_INFORMATION
 *     尺寸断言与 cb 字段按架构取值（ia32: 68/16，x64: 104/24）
 *
 * 用法：node apply-patches.js <app目录>
 */
const fs = require('node:fs');
const path = require('node:path');

const APP = process.argv[2] || path.resolve(__dirname, '..', 'app');

function read(p) { return fs.readFileSync(p, 'utf8'); }
function write(p, c) { fs.writeFileSync(p, c, 'utf8'); }

// ── 1. ia32 shim ──────────────────────────────────────────────────────────
const shimSrc = path.join(__dirname, 'ia32-shim.js');
const shimDst = path.join(APP, 'node_modules', 'node-pty', 'lib', 'ia32-shim.js');
fs.copyFileSync(shimSrc, shimDst);
console.log('[patches] written', path.relative(APP, shimDst));

// ── 2. node-pty index.js 分流 ─────────────────────────────────────────────
const ptyIndex = path.join(APP, 'node_modules', 'node-pty', 'lib', 'index.js');
const PATCH_MARK = "DSH portable patch: no win32-ia32 native prebuild";
let ptySrc = read(ptyIndex);
if (!ptySrc.includes(PATCH_MARK)) {
  ptySrc = ptySrc.replace(
    `Object.defineProperty(exports, "__esModule", { value: true });`,
    `// ${PATCH_MARK} exists for node-pty;\n// on 32-bit Windows load the pure-JS shim instead of throwing at boot.\nif (process.arch === 'ia32') {\n  module.exports = require('./ia32-shim.js');\n  return;\n}\nObject.defineProperty(exports, "__esModule", { value: true });`
  );
  write(ptyIndex, ptySrc);
  console.log('[patches] patched', path.relative(APP, ptyIndex));
} else {
  console.log('[patches] already patched', path.relative(APP, ptyIndex));
}

// ── 3. sandbox-windows-acl 布局断言 ───────────────────────────────────────
const aclDir = path.join(APP, 'node_modules', '@deepseek-ai', 'dsh-sandbox-windows-acl', 'lib');
const aclFile = fs.readdirSync(aclDir).find((f) => /^types-.*\.js$/.test(f));
if (!aclFile) throw new Error('sandbox-windows-acl types file not found');
const aclPath = path.join(aclDir, aclFile);
let aclSrc = read(aclPath);
if (!aclSrc.includes('DSH portable patch')) {
  aclSrc = aclSrc.replace(
    `if (STARTUPINFOW.size !== 104) throw new Error(\`STARTUPINFOW layout mismatch: koffi computed \${STARTUPINFOW.size}, header probe says 104\`);`,
    `if (STARTUPINFOW.size !== (process.arch === 'ia32' ? 68 : 104)) throw new Error(\`STARTUPINFOW layout mismatch: koffi computed \${STARTUPINFOW.size}, header probe says \${process.arch === 'ia32' ? 68 : 104}\`);`
  );
  aclSrc = aclSrc.replace(
    `if (PROCESS_INFORMATION.size !== 24) throw new Error(\`PROCESS_INFORMATION layout mismatch: koffi computed \${PROCESS_INFORMATION.size}, header probe says 24\`);`,
    `if (PROCESS_INFORMATION.size !== (process.arch === 'ia32' ? 16 : 24)) throw new Error(\`PROCESS_INFORMATION layout mismatch: koffi computed \${PROCESS_INFORMATION.size}, header probe says \${process.arch === 'ia32' ? 16 : 24}\`);`
  );
  aclSrc = aclSrc.replace(/cb: 104,/g, `cb: process.arch === 'ia32' ? 68 : 104,`);
  aclSrc = aclSrc.replace(
    `/* v8 ignore start -- layout-mismatch guards fire only on ABI breakage; verify/abi-probe.cpp pins both sizes. */`,
    `/* v8 ignore start -- layout-mismatch guards fire only on ABI breakage; verify/abi-probe.cpp pins both sizes. */\n/* DSH portable patch: STARTUPINFOW/PROCESS_INFORMATION are arch-dependent (68/16 on ia32, 104/24 on x64). */`
  );
  write(aclPath, aclSrc);
  console.log('[patches] patched', path.relative(APP, aclPath));
} else {
  console.log('[patches] already patched', path.relative(APP, aclPath));
}

console.log('[patches] done');
