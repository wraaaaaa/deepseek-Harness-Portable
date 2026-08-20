'use strict';
/**
 * DSH 便携版唯一引导模块（x64 Electron 入口与 x86 浏览器入口共用）。
 *
 * 职责：
 *  1. 注入"本体无痕"环境变量：DSH_HOME / TMP / TEMP / npm 缓存 / pnpm store 全部收敛到 data/；
 *  2. 文件系统兼容：DSH 需要 NTFS 的 junction（符号链接）。若 data 所在盘不支持
 *     （如 exFAT/FAT32 U 盘），自动把 data 降级到本机 %LOCALAPPDATA%\DSH-Portable\data；
 *  3. 自愈：启动前清理 data/server.pid 残留进程 + 删除 data/profiles/node_modules
 *     （该目录是 DSH 维护的 junction 回退，复制/移动文件夹时会被解引用成真实目录或
 *     残留空目录，导致 "exists and is not a symlink" 崩溃）；
 *  4. 以 `--port 0` 拉起 `node app/.../bin.js web`，由 OS 分配空闲端口；
 *  5. 从 stdout 解析 `dsh web: http://127.0.0.1:<port>` 后轮询到 200；
 *  6. 提供 stop()：taskkill 进程树 + 清理 pid 文件。
 *
 * 纯 CJS、零第三方依赖，可在 Electron 主进程或裸 Node 下运行。
 */
const { spawn, execFileSync } = require('node:child_process');
const {
  existsSync, mkdirSync, writeFileSync, readFileSync, unlinkSync,
  appendFileSync, rmSync, symlinkSync,
} = require('node:fs');
const { join, resolve } = require('node:path');
const { homedir } = require('node:os');

/** 包根目录（shell/ 的上一级）。 */
const FOLDER = resolve(__dirname, '..');

const BIN = join(FOLDER, 'app', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js');
const BOOT_TIMEOUT_MS = 120000;

function rootPath(...segments) {
  return join(FOLDER, ...segments);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** 降级目录：本机用户目录下的 NTFS 位置。 */
function fallbackDataDir() {
  const base = process.env.LOCALAPPDATA || join(homedir(), 'AppData', 'Local');
  return join(base, 'DSH-Portable', 'data');
}

/**
 * 探测目录所在文件系统是否支持 junction（NTFS 支持，exFAT/FAT32 不支持）。
 * 通过"实际创建一次 junction"来判断，避免依赖文件系统名。
 */
function supportsJunction(dir) {
  mkdirSync(dir, { recursive: true });
  const probeTarget = join(dir, '.probe-target');
  const probeLink = join(dir, '.probe-link');
  try {
    writeFileSync(probeTarget, 'x');
    symlinkSync(probeTarget, probeLink, 'junction');
  } catch (_) {
    // 失败：清理可能残留的空目录（Windows 上建 junction 失败常留下空目录）
    try { rmSync(probeLink, { recursive: true, force: true }); } catch (_e) { /* 忽略 */ }
    try { unlinkSync(probeLink); } catch (_e) { /* 忽略 */ }
    try { unlinkSync(probeTarget); } catch (_e) { /* 忽略 */ }
    return false;
  }
  // 成功：清理探针
  try { unlinkSync(probeLink); } catch (_e) { /* 忽略 */ }
  try { unlinkSync(probeTarget); } catch (_e) { /* 忽略 */ }
  return true;
}

/**
 * 决定 data 目录：优先包内 data/，若其文件系统不支持 junction 则降级到本机。
 * 环境变量 DSH_PORTABLE_FORCE_DEGRADE=1 可强制降级（测试/手动开关）。
 */
function resolveDataDir() {
  const preferred = rootPath('data');
  if (process.env.DSH_PORTABLE_FORCE_DEGRADE === '1') {
    return { dataDir: fallbackDataDir(), degraded: true, reason: 'forced' };
  }
  if (supportsJunction(preferred)) {
    return { dataDir: preferred, degraded: false, reason: '' };
  }
  return { dataDir: fallbackDataDir(), degraded: true, reason: 'no-junction' };
}

/**
 * 构建子进程环境：本体数据全部指向给定 dataDir。
 * @param {'x64'|'x86'} arch
 * @param {string} dataDir
 */
function buildEnv(arch, dataDir) {
  const tmpDir = join(dataDir, 'tmp');
  mkdirSync(tmpDir, { recursive: true });
  const nodeDir = rootPath('node', arch === 'x86' ? 'win-x86' : 'win-x64');
  const toolsDir = rootPath('tools');
  const env = { ...process.env };
  env.DSH_HOME = dataDir;
  env.TMP = tmpDir;
  env.TEMP = tmpDir;
  env.npm_config_cache = join(dataDir, 'npm-cache');
  env.npm_config_store_dir = join(dataDir, 'pnpm-store');
  const extra = [nodeDir, toolsDir].filter((d) => existsSync(d));
  env.PATH = [...extra, env.PATH || ''].join(';');
  return { env, dataDir, tmpDir };
}

/**
 * 首次运行时把 pnpm 的 store/cache 锁进包内。
 * pnpm 11 起项目级配置读 pnpm-workspace.yaml（.npmrc 已不再被读取）；
 * 路径用正斜杠以免 YAML 转义错误。仅在缺少时追加，不覆盖现有内容。
 */
function ensurePnpmConfig(dataDir) {
  const dir = join(dataDir, 'profiles', 'web');
  mkdirSync(dir, { recursive: true });
  const ws = join(dir, 'pnpm-workspace.yaml');
  const store = join(dataDir, 'pnpm-store').replace(/\\/g, '/');
  const cache = join(dataDir, 'pnpm-cache').replace(/\\/g, '/');
  try {
    const content = existsSync(ws) ? readFileSync(ws, 'utf8') : '';
    if (!content.includes('storeDir')) {
      writeFileSync(ws, `${content.trimEnd()}\nstoreDir: ${store}\n`, 'utf8');
    }
    if (!content.includes('cacheDir')) {
      const updated = readFileSync(ws, 'utf8');
      writeFileSync(ws, `${updated.trimEnd()}\ncacheDir: ${cache}\n`, 'utf8');
    }
  } catch (e) {
    log(dataDir, `[boot] ensurePnpmConfig failed: ${String(e)}`);
  }
}

function killTree(pid) {
  if (!pid) return;
  try {
    execFileSync('taskkill', ['/PID', String(pid), '/T', '/F'], { stdio: 'ignore' });
  } catch (_) { /* 进程已不在，忽略 */ }
}

function readPidFile(pidFile) {
  try {
    const v = readFileSync(pidFile, 'utf8').trim();
    return v ? Number(v) : 0;
  } catch (_) {
    return 0;
  }
}

function log(dataDir, line) {
  try {
    appendFileSync(join(dataDir, 'server.log'), `${line}\n`);
  } catch (_) { /* 日志写失败不致命 */ }
}

/**
 * 启动 DSH web 服务并等待就绪。
 * @param {{arch?: 'x64'|'x86', workspace?: string}} options
 * @returns {Promise<{url: string, port: number, stop: () => void, degraded: boolean, dataDir: string}>}
 */
async function startServer(options) {
  const arch = options.arch || 'x64';

  const { dataDir, degraded, reason } = resolveDataDir();
  if (degraded) {
    const line = `[boot] WARNING: junction not supported (${reason}); data relocated to ${dataDir}`;
    console.log(line);
    log(dataDir, line);
  }

  const { env } = buildEnv(arch, dataDir);
  ensurePnpmConfig(dataDir);

  // 自愈：删除 DSH 维护的 junction 回退目录。该目录只有指向 app/node_modules 的
  // 符号链接，复制/移动文件夹时会被解引用成真实目录、或在 exFAT 上残留空目录，
  // 导致启动报 "exists and is not a symlink"。删掉后 DSH 会重新 heal 重建（NTFS 秒建）。
  try {
    rmSync(join(dataDir, 'profiles', 'node_modules'), { recursive: true, force: true });
  } catch (_) { /* 不存在或只读时忽略 */ }

  const pidFile = join(dataDir, 'server.pid');
  const oldPid = readPidFile(pidFile);
  if (oldPid) {
    log(dataDir, `[boot] cleaning leftover server pid ${oldPid}`);
    killTree(oldPid);
  }

  const nodeExe = join(rootPath('node', arch === 'x86' ? 'win-x86' : 'win-x64'), 'node.exe');
  const cwd = options.workspace || homedir();
  mkdirSync(cwd, { recursive: true });

  log(dataDir, `[boot] spawning server (arch=${arch}, cwd=${cwd})`);
  const child = spawn(nodeExe, [BIN, 'web', '--port', '0'], {
    env,
    cwd,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: false,
  });
  writeFileSync(pidFile, String(child.pid));

  let exited = false;
  let exitCode = null;
  let stderrTail = '';
  let stdoutBuf = '';
  child.stderr.on('data', (d) => {
    stderrTail = (stderrTail + d.toString()).slice(-8192);
    log(dataDir, `[server:stderr] ${d.toString().trimEnd()}`);
  });
  child.stdout.on('data', (d) => {
    stdoutBuf += d.toString();
    log(dataDir, `[server:stdout] ${d.toString().trimEnd()}`);
  });
  child.on('exit', (code) => {
    exited = true;
    exitCode = code;
    log(dataDir, `[server] exited code=${code}`);
  });
  child.on('error', (e) => {
    exited = true;
    log(dataDir, `[server] spawn error: ${String(e)}`);
  });

  const stop = () => {
    try { unlinkSync(pidFile); } catch (_) { /* 已删 */ }
    if (child.pid) killTree(child.pid);
  };

  // 等待：进程退出 或 stdout 中出现 "dsh web: http://127.0.0.1:<port>"
  const urlPattern = /dsh web:\s*(http:\/\/127\.0\.0\.1:\d+)/;
  const deadline = Date.now() + BOOT_TIMEOUT_MS;
  let url = null;

  while (Date.now() < deadline) {
    if (exited) {
      throw new Error(
        `DSH 服务启动失败（exit=${exitCode}）。\n${stderrTail || '(无 stderr 输出)'}\n详见 ${join(dataDir, 'server.log')}`
      );
    }
    const match = urlPattern.exec(stdoutBuf);
    if (match) {
      url = match[1];
      break;
    }
    await sleep(200);
  }

  if (!url) {
    stop();
    throw new Error(
      `DSH 服务在 ${BOOT_TIMEOUT_MS / 1000}s 内未输出就绪地址（进程仍存活，疑似启动卡死）。\n详见 ${join(dataDir, 'server.log')}`
    );
  }

  // URL 行打印时树已完全就绪，但仍轮询到 200 以稳妥确认。
  const port = Number(new URL(url).port);
  const okDeadline = Date.now() + 15000;
  let ok = false;
  while (Date.now() < okDeadline) {
    if (exited) break;
    try {
      const res = await fetch(url, { method: 'GET' });
      if (res.ok) {
        ok = true;
        break;
      }
    } catch (_) { /* 继续等 */ }
    await sleep(250);
  }
  if (!ok) {
    stop();
    throw new Error(`DSH 服务已打印地址 ${url} 但 15s 内未响应 HTTP；详见 ${join(dataDir, 'server.log')}`);
  }

  log(dataDir, `[boot] ready at ${url}`);
  return { url, port, stop, degraded, dataDir };
}

module.exports = { startServer, FOLDER, BOOT_TIMEOUT_MS };
