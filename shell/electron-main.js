'use strict';
/**
 * DSH 便携版 x64 主入口：Electron 窗口壳。
 *
 * 只做四件事：
 *  1. 把 Electron 的一切用户数据（缓存/GPU/Cookie/Crashpad）重定向到包内 data/electron；
 *  2. 通过 server-boot.js 拉起 DSH web 服务（bundled node.exe）；
 *  3. 服务就绪后开 BrowserWindow 加载 http://127.0.0.1:<port>；
 *  4. 窗口关闭时优雅停服并退出。
 */
const { app, BrowserWindow, dialog } = require('electron');
const { join, resolve } = require('node:path');
const { appendFileSync } = require('node:fs');
const { startServer } = require('./server-boot.js');

const FOLDER = resolve(__dirname, '..');

function elog(line) {
  try {
    appendFileSync(join(FOLDER, 'data', 'electron-boot.log'), `${new Date().toISOString()} ${line}\n`);
  } catch (_) { /* 日志写失败不致命 */ }
}

// 必须赶在 app ready / 任何 Chromium 组件触碰磁盘之前设置 userData。
app.setPath('userData', join(FOLDER, 'data', 'electron'));
app.setPath('sessionData', join(FOLDER, 'data', 'electron'));

// 单实例锁：重复启动时聚焦已有窗口，避免两个服务抢端口。
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  let mainWindow = null;
  let server = null;

  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  async function boot() {
    try {
      server = await startServer({ arch: 'x64' });
    } catch (err) {
      dialog.showErrorBox('DSH 启动失败', String(err && err.message ? err.message : err));
      app.exit(1);
      return;
    }
    if (server.degraded) {
      dialog.showMessageBox({
        type: 'warning',
        title: 'DSH 提示',
        message: '当前盘不支持符号链接（如 exFAT / FAT32）',
        detail: `DSH 本体数据已改存到本机：${server.dataDir}\n功能完全正常，但这些数据不会随本文件夹一起带走。\n如需完全便携，请把文件夹放到 NTFS 盘。`,
      });
    }
    createWindow(server.url);
  }

  function createWindow(url) {
    mainWindow = new BrowserWindow({
      width: 1280,
      height: 820,
      title: 'DeepSeek Harness',
      autoHideMenuBar: true,
      icon: join(FOLDER, 'shell', 'favicon.png'),
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
      },
    });
    mainWindow.webContents.on('did-finish-load', () => {
      elog(`did-finish-load ${url}`);
    });
    mainWindow.webContents.on('did-fail-load', (_e, code, desc, failedUrl) => {
      elog(`did-fail-load code=${code} desc=${desc} url=${failedUrl}`);
    });
    mainWindow.webContents.on('render-process-gone', (_e, details) => {
      elog(`render-process-gone reason=${details.reason}`);
    });
    mainWindow.loadURL(url);
    mainWindow.on('closed', () => {
      mainWindow = null;
      if (server) {
        server.stop();
        server = null;
      }
      app.quit();
    });
  }

  app.whenReady().then(boot);
  app.on('window-all-closed', () => {
    // Windows：窗口全关即退出（默认行为，双保险）
    if (server) {
      server.stop();
      server = null;
    }
    app.quit();
  });
  app.on('will-quit', () => {
    if (server) {
      server.stop();
      server = null;
    }
  });
}
