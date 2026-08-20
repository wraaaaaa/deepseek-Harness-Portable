# ============================================================
#  DSH Portable - one-click kernel upgrade
#  Rebuilds app/ from npm (new DSH version), backs up data/ first,
#  then re-applies the ia32 compat patches. Node/Electron/pnpm are NOT touched.
#
#  Usage: powershell -File upgrade.ps1 [-Version <ver>]
#   -Version: target DSH version (default: latest on npm)
#
#  The ia32 native-package versions below follow the koffi/sharp/
#  node-addon-require-builtin versions pinned in build.ps1. If a DSH
#  upgrade bumps those, update them to match.
# ============================================================
param(
  [string]$Version = "latest",
  [string]$KoffiIa32 = "3.1.5",
  [string]$SharpIa32 = "0.35.3",
  [string]$RequireBuiltinIa32 = "0.1.5"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$app  = Join-Path $Root "app"

function Read-DshVersion($dir) {
  $pkg = Join-Path $dir "node_modules\@deepseek-ai\dsh\package.json"
  if (Test-Path $pkg) {
    try { return (Get-Content $pkg -Raw | ConvertFrom-Json).version } catch { return "?" }
  }
  return "(none)"
}

# 1. current version
$oldVer = Read-DshVersion $app
Write-Host "==> current DSH version: $oldVer"
Write-Host "==> target DSH version: $Version"

# 2. backup data (settings / sessions / credentials)
$data = Join-Path $Root "data"
if (Test-Path $data) {
  $ts  = Get-Date -Format "yyyyMMdd-HHmmss"
  $bak = Join-Path $Root "data-backup-$ts"
  Copy-Item $data $bak -Recurse -Force
  Write-Host "==> data backed up to: $bak"
} else {
  Write-Host "==> no data/ to back up"
}

# 3. rebuild kernel
if (Test-Path $app) { Remove-Item $app -Recurse -Force }
New-Item -ItemType Directory -Path $app -Force | Out-Null
Write-Host "==> npm install @deepseek-ai/dsh@$Version ..."
npm install --prefix $app --no-audit --no-fund "@deepseek-ai/dsh@$Version"
if ($LASTEXITCODE -ne 0) { throw "npm install failed" }

# 3b. ia32 native modules (npm on x64 only installs x64 platform packages)
npm install --prefix $app --no-save --no-audit --no-fund `
  "@koromix/koffi-win32-ia32@$KoffiIa32" `
  "@img/sharp-win32-ia32@$SharpIa32" `
  "node-addon-require-builtin-win32-ia32-msvc@$RequireBuiltinIa32"
if ($LASTEXITCODE -ne 0) { throw "ia32 install failed" }

# 4. apply ia32 compat patches (idempotent)
$nodeBin = Join-Path $Root "node\win-x64\node.exe"
if (Test-Path $nodeBin) {
  & $nodeBin (Join-Path $Root "patches\apply-patches.js") $app
} else {
  & node (Join-Path $Root "patches\apply-patches.js") $app
}
if ($LASTEXITCODE -ne 0) { throw "patch application failed" }

# 5. verify
$bin = Join-Path $app "node_modules\@deepseek-ai\dsh\lib\bin.js"
if (-not (Test-Path $bin)) { throw "after upgrade, bin.js is missing" }
$newVer = Read-DshVersion $app
Write-Host ("==> upgrade complete: {0} -> {1}" -f $oldVer, $newVer)
Write-Host "==> old data is in data-backup-*; rename it back to 'data' to roll back"
