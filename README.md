# DeepSeek Harness 便携版（DSH Portable）

把整套 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）连同它的运行环境，打包成一个**免安装、点击即用、本体零残留**的自包含文件夹。

- **64 位 Windows**：双击 `启动DSH.bat` → 独立应用窗口（Electron 壳）
- **32 位 Windows**：双击 `启动DSH.bat` → 自动改用系统浏览器打开

无需安装 Node.js、npm、pnpm，也无需任何开发环境。

---

## 目录

1. [这是什么 / 解决什么问题](#1-这是什么--解决什么问题)
2. [工作原理（原理篇）](#2-工作原理原理篇)
3. [为什么这样设计（为什么篇）](#3-为什么这样设计为什么篇)
4. [与官方 DSH 的差异（务必阅读）](#4-与官方-dsh-的差异务必阅读)
5. [下载](#5-下载)
6. [使用教程](#6-使用教程)
7. [从源码构建](#7-从源码构建)
8. [目录结构](#8-目录结构)
9. [常见问题](#9-常见问题)
10. [许可证](#10-许可证)

---

## 1. 这是什么 / 解决什么问题

DSH 本身是一个 **npm 包**（`@deepseek-ai/dsh`），正常运行需要先装 Node.js、再 `npx @deepseek-ai/dsh web`，把一堆数据散落在 `~/.dsh` 和系统缓存里。对普通用户来说有三道门槛：

1. **要装环境**：Node.js、npm、pnpm……缺一个就跑不起来；
2. **不干净**：会话、凭据、缓存写进系统目录，卸载/删除时留下痕迹；
3. **不好分发**：没法"拷一个文件夹给同事双击就用"。

本项目的目标就是消除这三道门槛：**一个文件夹 = 完整可运行的 DSH**，双击即用；**应用本体的一切数据都在文件夹内**，删除文件夹即零残留；而你**在项目里干的活的成果，永远留在你的电脑上**。

---

## 2. 工作原理（原理篇）

### 2.1 DSH 本质：一个 Node 服务 + 一个内置网页前端

DSH 的运行方式其实很朴素：

```
node bin.js web          # 启动一个本地 HTTP 服务
  └─ 默认监听 127.0.0.1:3080
  └─ 前端 HTML/JS（dist，约 4MB）直接内置在 npm 包 dsh-web-frontend 里
```

也就是说，DSH 的"界面"并不是一个桌面程序，而是**浏览器里打开的网页**，网页由本机上的一个 Node 进程提供。这给我们留了一个绝佳的打包切入点：**界面用什么包并不重要，只要能打开这个本地网址即可。**

### 2.2 便携版的架构

```
┌───────────────────────────────────────────────────────────┐
│  你双击「启动DSH.bat」                                        │
├───────────────────────────────────────────────────────────┤
│  64 位：electron.exe 启动 shell/electron-main.js            │
│  32 位：node.exe(win-x86) 启动 shell/browser-launch.js      │
│         │                                                  │
│         ▼ 两者共用同一个引导模块 shell/server-boot.js         │
│  1. 注入环境变量（见 2.3 无痕原理）                            │
│  2. 用内置 node.exe 拉起：                                    │
│       app/node_modules/@deepseek-ai/dsh/lib/bin.js web --port 0 │
│     （--port 0 = 让系统自动挑空闲端口，永不冲突）              │
│  3. 从子进程输出解析出真实地址 "dsh web: http://127.0.0.1:<port>" │
│  4. 轮询该地址直到返回 200（服务就绪）                          │
├───────────────────────────────────────────────────────────┤
│  64 位：Electron 开一个 BrowserWindow 加载该网址（窗口软件）   │
│  32 位：start 打开系统默认浏览器加载该网址                      │
├───────────────────────────────────────────────────────────┤
│  DSH 内核（app/）：与原版 @deepseek-ai/dsh 完全一致，原样运行    │
└───────────────────────────────────────────────────────────┘
```

关键点：**我们没有改动 DSH 的一行逻辑**。DSH 还是那个 DSH，我们只是在它外面套了一层"启动器壳"，壳只负责三件事——**设环境变量、拉起服务、打开界面**。

### 2.3 "本体无痕"是怎么做到的

DSH 和它的依赖会把数据写到很多地方。我们的做法是：**用环境变量和配置，把这些位置全部重定向进文件夹内的 `data/`**。启动器给服务进程注入：

| 原本写到哪 | 重定向到 | 说明 |
|---|---|---|
| `~/.dsh`（会话/设置/凭据/插件） | `data/` | 通过 `DSH_HOME` 环境变量 |
| 系统临时目录（spill、图片处理等） | `data/tmp` | 通过 `TMP`/`TEMP` |
| pnpm 全局 store/cache | `data/pnpm-store`、`data/pnpm-cache` | 写入 `pnpm-workspace.yaml` |
| Electron(Chromium) 的缓存/GPU/Cookie | `data/electron` | `app.setPath('userData', ...)` |

于是：**删除整个文件夹 → 应用本体在电脑上不留下任何痕迹**（系统级事件日志、杀软扫描记录这类"系统行为"除外，见常见问题）。

### 2.4 "成果保留"是怎么做到的

"无痕"只针对 **DSH 应用本体**，不针对你**用 DSH 干的活**。

- DSH 的默认工作区（workspace）就是启动目录；便携版默认把它设为**你的用户主目录**，你也可以在界面里随时切到任意项目文件夹（比如你的 Minecraft 项目）。
- agent 生成的所有文件，都写在你选定的项目文件夹里 —— 那是**你的成果**，删除本 DSH 文件夹后原样保留。
- 只有 DSH 自身的数据（会话记录、设置、API Key、插件、缓存）在 `data/` 里，随文件夹删除而消失。

一句话：**删掉的是"工具"，留下的是"作品"。**

### 2.5 一份内核如何同时支持 64 位和 32 位

原生模块（node-pty、sharp、koffi 等）是按 CPU 架构编译的。便携版的做法是：

- **两份 Node 运行时**：`node/win-x64`（Node 24）与 `node/win-x86`（Node 22，官方最后一个还出 32 位版的系列）；
- **原生模块两套共存**：`app/node_modules` 里同时放 x64 与 ia32 的平台包，Node 的加载器会按 `process.platform`/`process.arch` 自动挑选正确的一份；
- **壳最简**：64 位用 Electron 窗口，32 位退回"启动器 + 系统浏览器"，共享同一套内核与引导逻辑，功能完全一致。

---

## 3. 为什么这样设计（为什么篇）

### 3.1 为什么不编译成"单个 exe"？

常见做法是把 Node 程序用 pkg / Node SEA / bun build 打成单个可执行文件。对 DSH 不适用，原因是**它依赖原生二进制模块**：

- `node-pty`（终端）、`sharp`（图片处理）、`koffi`（Windows ACL/目录选择器）、`node-addon-require-builtin`（插件加载器）都是编译出的 `.node` 二进制；
- 单文件打包器要么不支持把原生模块塞进包里，要么要求目标机器有完整工具链，等于又退回了"要装环境"。

所以"便携文件夹"才是这类程序的正解：**把 Node 运行时和原生模块原样带上，谁都不需要装。**

### 3.2 为什么 64 位用 Electron 壳、32 位用浏览器？

用户要的是"点击出来一个窗口"的软件感，于是 64 位用 Electron 包一个窗口。但有两个硬事实：

1. **Electron 官方已移除 32 位 Windows 构建**（[electron/electron#52326](https://github.com/electron/electron/pull/52326)）；
2. 32 位本来只是"极简兼容"的次要目标。

因此 32 位退而求其次：**同一个内核 + 一个 100 行的启动脚本 + 系统自带的浏览器**。功能上两者完全一致，只是"窗口"换成了"浏览器标签页"。

### 3.3 为什么"源码进仓库、二进制进 Release"？

这个仓库里**没有** `app/`、`node/`、`electron/`、`tools/` 这些大二进制（共约 800MB），原因是一个 GitHub 的硬限制：

- **GitHub 拒绝单个超过 100MB 的文件**。而 `electron.exe` 就有 225MB；
- 即使改用 Git LFS 存大文件，公开仓库也会受 **LFS 免费额度（1GB 存储 / 每月 1GB 流量）** 限制——别人 clone 两次就耗尽当月流量，仓库就"拉不动"了。

业界对"大软件 + GitHub"的标准解法正是：

> **代码进仓库，二进制进 Release。**

- **仓库**：只放源码（引导壳、构建脚本、补丁、文档），几十 MB，干净、可 diff、可协作；
- **Release**：把构建好的便携版打成 zip 作为附件（GitHub Release 单文件上限 2GB，下载方无任何额度限制）。

所以：**普通用户下载 Release 的 zip 点击即用；开发者 clone 仓库后跑 `build.ps1` 即可本地重建。**

### 3.4 为什么构建脚本用 npm 现装内核，而不是提交 node_modules？

`app/node_modules` 有约 2.4 万个文件、239MB，全部提交进 git 既臃肿又难审阅。而 DSH 本身就是发布在 npm 上的包，用内置 pnpm 一条命令 `pnpm add @deepseek-ai/dsh@0.1.1-rc.2` 就能**从官方源原样还原内核**（注意：用 npm 会因 DSH 庞大的 peer 依赖图卡死，构建脚本已改用 pnpm 扁平布局）——这比提交一份二进制快照更透明、更可验证（你能对着 npm 源审计每一个文件）。

---

## 4. 与官方 DSH 的差异（务必阅读）

**核心结论：64 位路径 = 纯原版 DSH，零修改生效；两处补丁只在 32 位架构下激活。**

| 补丁 | 作用对象 | 为什么 | 64 位影响 | 32 位影响 |
|---|---|---|---|---|
| `node-pty` 纯 JS 垫片 | 第三方依赖（非 DSH） | 官方与所有 fork 均不提供 win32-ia32 预编译 | **无**（x64 走原生二进制，垫片分支不进入） | 终端由垫片实现（能跑命令、可输入输出，但无完整 PTY 语义） |
| `dsh-sandbox-windows-acl` 结构尺寸按架构取值 | DSH 自带的 Windows 沙箱包 | 官方把 Windows 结构体尺寸硬编码为 64 位的值（104/24），32 位应为 68/16 | **无**（`process.arch==='ia32'` 为假，取值仍是 104/24，行为逐字节一致） | 修正为 32 位正确布局，沙箱正常工作 |

两处补丁的完整源码在 [`patches/`](patches/)（`apply-patches.js` 幂等应用，`ia32-shim.js` 是垫脚本体），可逐行审阅。**64 位用户得到的是一份行为与官方 `@deepseek-ai/dsh@0.1.1-rc.2` 完全一致的 DSH。**

> 注：DSH 版本为 **0.1.1-rc.2**（发布前候选版）。将来官方发正式版后，双击 `升级DSH.bat`（或 `powershell -File upgrade.ps1 -Version <版本>`）即可一键升级内核，脚本会自动备份 `data/`。

---

## 5. 下载

### 方式一（推荐）：下载 Release 的便携包

1. 打开本仓库的 [**Releases**](../../releases) 页；
2. 找到 **v1.0α**（或最新版）；
3. 下载附件 `DSH-Portable-v1.0α.zip`；
4. 解压到任意可写位置（桌面、D 盘均可，路径含中文/空格没问题），按[使用教程](#6-使用教程)双击即用。

### 方式二：clone 源码后本地构建

```powershell
git clone https://github.com/wraaaaaa/deepseek-Harness-Portable.git
cd deepseek-Harness-Portable
powershell -File build.ps1 -Zip      # 一键构建并打包
```

构建产物在 `dist/` 下。详见[从源码构建](#7-从源码构建)。

---

## 6. 使用教程

### 6.1 第一次启动

1. 把解压出来的整个文件夹放到任意**可写**位置（不要放进 `Program Files` 这类只读目录）；
2. 双击 `启动DSH.bat`；
3. 首次启动需要等几秒到十几秒（会自动在文件夹内初始化 `data/`）；
4. 64 位会弹出独立窗口，32 位会打开浏览器标签页；
5. 在「设置」里填入你的 **DeepSeek API Key**（只填这一次，保存在 `data/` 内，不会上传到任何地方）。

### 6.2 日常使用

- 所有功能与原版 DSH 一致：文件读写、PowerShell 命令、联网搜索、子代理、工作流、目标、计划模式、技能、插件管理……一个不少。
- **切换工作区**：界面里选择/浏览你的项目文件夹（例如 `D:\开发\...`）。agent 生成的文件会落在那里，删除本软件不影响它们。

### 6.3 安装插件（随时带走）

本包内置了独立版 pnpm。在任意终端执行（把 `<文件夹>` 换成实际路径）：

```bat
set DSH_HOME=<文件夹>\data
<文件夹>\node\win-x64\node.exe <文件夹>\app\node_modules\@deepseek-ai\dsh\lib\bin.js plugin --profile web add <插件包名>
```

安装的插件写入 `data\profiles\web\`，pnpm 的 store/缓存也锁在包内——**换台电脑，整个文件夹拷过去，插件和会话一样都在**。（安装插件需联网访问 npm 仓库，插件来源请自行甄别。）

### 6.4 删除 / 迁移

- 想彻底卸载：**直接删除整个文件夹**即可。DSH 本体的数据随文件夹消失，不会在系统里留 `~/.dsh`、`%APPDATA%` 或缓存痕迹。
- 想迁移到另一台电脑：整个文件夹拷过去即可（数据在 `data/` 里）。注意 API Key 也随 `data/` 一起，请勿把 `data/` 分享给他人。

### 6.5 放 U 盘 / 移动盘：文件系统要求（重要）

DSH 依赖 **NTFS 的符号链接（junction）**。如果你把文件夹放到 U 盘/移动硬盘，请先确认该盘是 **NTFS**：

- **NTFS**：完全便携，数据随包，一切正常；
- **exFAT / FAT32**（U 盘出厂常见）：**不支持符号链接**，启动时 DSH 会自动把本体数据（会话/设置/凭据）降级存到本机 `%LOCALAPPDATA%\DSH-Portable\data`，并弹出提示。功能完全正常，但**这些数据不会随 U 盘带走**。

如果你需要"U 盘随身 + 数据随包"，把 U 盘**格式化成 NTFS** 即可（格式化会清空 U 盘，请先备份）。

---

## 7. 从源码构建

### 7.1 依赖

- Windows 10/11（构建 64 位版；32 位运行时也会一并下载）
- 已安装 **PowerShell**（Windows 自带）与 **Node.js + npm**（仅构建机器需要，用来拉内核和 pnpm）
- 联网（下载内核、运行时、Electron、pnpm）

### 7.2 构建步骤

```powershell
git clone https://github.com/wraaaaaa/deepseek-Harness-Portable.git
cd deepseek-Harness-Portable

# 完整构建 + 打包 Release zip（首次约 10~30 分钟，取决于网速）
powershell -File build.ps1 -Zip
```

`build.ps1` 会依次：拉取官方 DSH 内核 → 补装 32 位模块 → 应用补丁 → 下载 Node x64/x86、Electron、pnpm → 组装并打包。

常用参数：

| 参数 | 作用 |
|---|---|
| `-SkipDownloads` | 跳过下载/安装（用于已有 `app/node/electron/tools` 时的增量重建） |
| `-Zip` | 额外生成 `dist/DSH-便携版-<版本>.zip`（Release 附件） |

### 7.3 冒烟自检

构建完成后可运行内置冒烟脚本，验证 64 位与 32 位内核都能完整启动：

```powershell
.\node\win-x64\node.exe .\patches\smoke-test.js x64
.\node\win-x86\node.exe .\patches\smoke-test.js x86
```

两条都以 `DONE` 且退出码 0 结束即为正常。

---

## 8. 目录结构

```
deepseek-Harness-Portable/
├─ 启动DSH.bat                 # 智能入口：检测系统位数分派
├─ 启动DSH-64位(窗口).bat       # 显式 64 位窗口入口
├─ 启动DSH-32位(浏览器).bat     # 显式 32 位浏览器入口
├─ shell/                      # 引导壳（源码，~150 行）
│  ├─ server-boot.js           # 唯一引导：注入环境变量 → 拉起服务 → 等就绪
│  ├─ electron-main.js         # 64 位：Electron 窗口壳
│  ├─ browser-launch.js        # 32 位：打开系统浏览器
│  └─ favicon.png              # 窗口图标
├─ patches/                    # 32 位兼容补丁 + 冒烟脚本（源码）
│  ├─ apply-patches.js         # 幂等补丁应用器
│  ├─ ia32-shim.js             # node-pty 32 位纯 JS 垫片
│  └─ smoke-test.js            # 双架构冒烟自检
├─ build.ps1                   # 一键构建脚本（源码）
├─ upgrade.ps1                 # 一键升级内核脚本（源码）
├─ 升级DSH.bat                  # 一键升级入口（双击，自动备份 data）
├─ licenses/                   # 开源许可证清单
├─ README.md                   # 本文件
├─ .gitignore                  # 忽略 app/node/electron/tools/data/dist
│
├─ app/                        # 【构建产物】DSH 内核（npm 安装，gitignore）
├─ node/win-x64/ node/win-x86/ # 【构建产物】内置 Node 运行时（gitignore）
├─ electron/                   # 【构建产物】Electron 运行时（gitignore）
├─ tools/                      # 【构建产物】pnpm 独立版（gitignore）
├─ data/                       # 【运行时】会话/设置/凭据/缓存（gitignore）
└─ dist/                       # 【构建产物】Release zip（gitignore）
```

> 仓库里只提交源码部分（`shell/`、`patches/`、`build.ps1`、启动脚本、`licenses/`、文档）；带 `【构建产物】` 的目录由 `build.ps1` 生成或运行时产生，均不入库。

---

## 9. 常见问题

**Q：双击没反应 / 报错？**
看 `data\server.log` 与 `data\electron-boot.log`（若存在）的最后几行，那里有启动全过程日志。

**Q：被杀毒软件 / SmartScreen 拦截？**
本包未做代码签名（签名证书需付费）。点「更多信息 → 仍要运行」即可。请确保来源可信（本仓库）后再放行。

**Q：端口冲突怎么办？**
不会冲突——服务端口由系统自动分配（`--port 0`），每次运行都不同。

**Q：能离线用吗？**
不能。DSH 是 DeepSeek 云端 API 的客户端，模型推理在云端，必须联网。

**Q：删了文件夹，电脑上还会留什么？**
DSH 本体零残留（数据全在 `data/` 里）。唯一无法避免的是**系统级痕迹**：Windows 事件日志里的进程记录、Defender 扫描记录、资源管理器的"最近使用"等——这些是操作系统行为，任何软件都无法消除，也不包含你的数据。

**Q：32 位和 64 位功能有区别吗？**
没有。同一套内核、同一套工具与预设。唯一差异在[第 4 节](#4-与官方-dsh-的差异务必阅读)已说明：32 位下终端由纯 JS 垫片实现（web 界面本就不提供终端入口，日常无感）。

**Q：怎么升级 DSH 版本？**
双击 `升级DSH.bat`（内部调 `upgrade.ps1`，默认升级到 npm 最新版）。它会先自动备份 `data/` 到 `data-backup-<时间戳>/`，再重建内核、重新应用补丁。要指定版本：`powershell -File upgrade.ps1 -Version 0.1.0-rc.8`。回滚：把 `data-backup-*` 改回 `data` 即可。

---

## 10. 许可证

- 本项目的引导壳、补丁、构建脚本按 **MIT** 许可分发（见 [`LICENSE`](LICENSE)）；
- 内核 `@deepseek-ai/dsh` 及其 `@deepseek-ai/*` 包均为 **MIT**（版权归 DeepSeek）；
- 各第三方依赖（Node.js、Electron、node-pty、sharp、koffi、pnpm、react 等）的许可证见 [`licenses/`](licenses/)，完整文本随各依赖包分发。
