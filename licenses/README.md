# 许可证清单（DSH 便携版）

本包由多个开源组件构成，各自采用以下许可证：

| 组件 | 版本 | 许可证 | 全文位置 |
|---|---|---|---|
| @deepseek-ai/dsh 及 @deepseek-ai/* 全部包 | 0.1.0-rc.7 | MIT | `app/node_modules/@deepseek-ai/*/LICENSE` |
| node-pty（含 DSH 便携补丁） | 1.2.0-beta.15 | MIT | `licenses/node-pty-LICENSE-MIT.txt` |
| sharp | 0.35.3 | Apache-2.0 | `licenses/sharp-LICENSE-Apache2.txt` |
| koffi | 3.1.5 | MIT | `licenses/koffi-LICENSE-MIT.txt` |
| Electron | 43.4.1 | MIT | `licenses/electron-LICENSE-MIT.txt` |
| Node.js（win-x64 / win-x86） | 24.19.0 / 22.23.0 | MIT | 官方 MIT 许可，见 https://github.com/nodejs/node/blob/main/LICENSE |
| pnpm | 11.22.0 | MIT | 官方 MIT 许可，见 https://github.com/pnpm/pnpm/blob/main/LICENSE |
| react / react-dom 等前端依赖 | — | MIT | `app/node_modules/*/LICENSE` |

说明：
- 各 npm 依赖的完整许可证文本随包附带，位于 `app/node_modules/<包名>/LICENSE`（或 LICENSE.md/LICENSE.txt）。
- 本包对 node-pty 与 @deepseek-ai/dsh-sandbox-windows-acl 应用了面向 32 位
  Windows 的小型补丁（见 `patches/apply-patches.js` 与 `patches/ia32-shim.js`），
  均为同一许可证下的兼容性修改，不改变原组件许可证。
- 重新分发本包时请保留本文件与上述许可证文本。
