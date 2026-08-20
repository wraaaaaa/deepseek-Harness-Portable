'use strict';
/**
 * DSH 便携版 x86 极简入口：Node 脚本 + 系统浏览器。
 *
 * 复用 server-boot.js 的完整引导（功能与 x64 完全一致），仅界面步骤不同：
 * 服务就绪后用系统默认浏览器打开，控制台窗口保持在前台显示服务日志，
 * Ctrl+C 或关闭窗口时停服。下次启动通过 data/server.pid 自愈清理残留。
 */
const { execFile } = require('node:child_process');
const { startServer } = require('./server-boot.js');

async function main() {
  console.log('[DSH 32位] 正在启动服务……');
  let server;
  try {
    server = await startServer({ arch: 'x86' });
  } catch (err) {
    console.error('[DSH 32位] 启动失败：');
    console.error(err && err.message ? err.message : String(err));
    process.exit(1);
  }
  console.log(`[DSH 32位] 服务就绪：${server.url}`);
  if (server.degraded) {
    console.log(`[DSH 32位] 提示：当前盘不支持符号链接（如 exFAT/FAT32），本体数据已改存到本机：${server.dataDir}`);
  }
  console.log('[DSH 32位] 正在打开浏览器……（关闭本窗口或按 Ctrl+C 即可退出）');

  // Windows `start` 是 cmd 内建命令，经 cmd /c 调用。
  execFile('cmd', ['/c', 'start', '', server.url], { windowsHide: true }, () => {});

  const stop = () => {
    console.log('[DSH 32位] 正在停止服务……');
    server.stop();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  process.on('exit', () => {
    // 兜底：进程无论如何退出都尽量清理服务树。
    try { server.stop(); } catch (_) { /* 忽略 */ }
  });

  // 保持进程存活：server 的 stdout/stderr 已被 server-boot 接管写日志。
  setInterval(() => {}, 1 << 30);
}

main().catch((err) => {
  console.error('[DSH 32位] 意外错误：', err);
  process.exit(1);
});
