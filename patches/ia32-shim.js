'use strict';
/**
 * DSH 便携版 x86 兼容垫片：node-pty 的纯 JS 替代实现。
 *
 * 背景：node-pty 官方与所有 fork 均不提供 win32-ia32 预编译二进制，
 * 而 `@deepseek-ai/dsh-subprocess-local` 在模块顶层无条件 `import * as nodePty`，
 * 若原生模块缺失会导致 32 位下整个 DSH 启动失败。
 *
 * 本垫片仅按 dsh 实际使用的 API 面（spawn 返回句柄的
 * pid/onData/onExit/write/kill）用 node:child_process 管道实现：
 * 进程能真实启动、stdin 可写、stdout/stderr 可读、退出可感知。
 * 不具备 PTY 语义（无 ConPTY、无 resize、stdout/stderr 合并）。
 *
 * 入口分流：见 node-pty/lib/index.js 顶部的 `process.arch === 'ia32'` 短路。
 */
const { spawn: cpSpawn, execFileSync } = require('node:child_process');

function shimSpawn(file, args, options) {
  const child = cpSpawn(file, args || [], {
    cwd: options && options.cwd,
    env: options && options.env,
    windowsHide: true,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const dataListeners = new Set();
  const exitListeners = new Set();

  const emitData = (chunk) => {
    for (const cb of [...dataListeners]) {
      try { cb(chunk); } catch (_) { /* 监听器自身异常不影响进程 */ }
    }
  };
  if (child.stdout) child.stdout.on('data', emitData);
  if (child.stderr) child.stderr.on('data', emitData);
  child.on('error', (err) => emitData(String(err) + '\n'));
  child.on('exit', (code, signal) => {
    const event = { exitCode: code, signal };
    for (const cb of [...exitListeners]) {
      try { cb(event); } catch (_) { /* 同上 */ }
    }
  });

  return {
    pid: child.pid,
    write(data) {
      if (child.stdin) {
        try { child.stdin.write(data); } catch (_) { /* 已退出 */ }
      }
    },
    kill(signal) {
      try { child.kill(signal || 'SIGTERM'); } catch (_) { /* 已退出 */ }
      try {
        execFileSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
      } catch (_) { /* 进程已不在 */ }
    },
    onData(callback) {
      dataListeners.add(callback);
      return () => dataListeners.delete(callback);
    },
    onExit(callback) {
      exitListeners.add(callback);
      return () => exitListeners.delete(callback);
    },
    resize() { /* 无 PTY，忽略 */ },
    pause() {},
    resume() {},
    clear() {},
    dispose() {},
  };
}

module.exports = {
  spawn: shimSpawn,
  fork: shimSpawn,
  createTerminal: shimSpawn,
  open() {
    throw new Error('node-pty open() 在 DSH 32 位兼容垫片中不可用');
  },
  native: null,
};
