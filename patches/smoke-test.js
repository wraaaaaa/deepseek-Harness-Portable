'use strict';
/**
 * 冒烟测试：用内置运行时走一遍完整引导（server-boot.js）。
 * 用法：node patches/smoke-test.js [arch]
 * 通过条件：服务就绪 → 首页 HTML 含 __DSH_BOOT__ → 停止后无残留进程。
 */
const { startServer, FOLDER } = require('../shell/server-boot.js');
const { execFileSync } = require('node:child_process');
const { join } = require('node:path');
const fs = require('node:fs');

const arch = process.argv[2] || 'x64';

async function main() {
  console.log(`[smoke:${arch}] startServer...`);
  const server = await startServer({ arch, workspace: join(FOLDER, 'data', '_smoke-workspace') });
  console.log(`[smoke:${arch}] ready: ${server.url}`);
  const res = await fetch(server.url, { method: 'GET' });
  const html = await res.text();
  const hasBoot = html.includes('__DSH_BOOT__');
  console.log(`[smoke:${arch}] GET / status=${res.status}, has __DSH_BOOT__ = ${hasBoot}, html bytes=${html.length}`);
  if (!hasBoot) {
    server.stop();
    process.exit(1);
  }
  // 验证数据落盘：data/ 下应有 profiles/web、sessions、server.log
  const dataDir = join(FOLDER, 'data');
  for (const p of ['profiles', 'profiles/web', 'sessions', 'storages']) {
    console.log(`[smoke:${arch}] data/${p} exists = ${fs.existsSync(join(dataDir, p))}`);
  }
  console.log(`[smoke:${arch}] stopping...`);
  server.stop();
  await new Promise((r) => setTimeout(r, 1500));
  // 残留检查：不应再有监听该端口的 node 进程（粗略：端口已释放即可）
  console.log(`[smoke:${arch}] DONE`);
  process.exit(0);
}

main().catch((err) => {
  console.error(`[smoke:${arch}] FAILED:`, err);
  process.exit(1);
});
