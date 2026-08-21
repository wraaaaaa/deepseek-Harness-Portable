# ============================================================
#  DSH Portable - one-click kernel upgrade (pnpm, hoisted layout)
#  Why pnpm instead of npm: npm 11's arborist hangs (100% CPU) on
#  DSH's huge peer-dependency graph; pnpm resolves it in seconds and
#  auto-installs peer deps. "nodeLinker: hoisted" gives the flat layout
#  DSH expects.
#
#  Usage: powershell -File upgrade.ps1 [-Version <ver>]
#   -Version: target DSH version (default: latest on npm)
# ============================================================
param(
  [string]$Version = "latest",
  [string]$KoffiIa32 = "3.1.6",
  [string]$SharpIa32 = "0.35.3",
  [string]$RequireBuiltinIa32 = "0.1.5"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$app  = Join-Path $Root "app"
$pnpm = Join-Path $Root "tools\pnpm.exe"

function Read-DshVersion($dir) {
  $pkg = Join-Path $dir "node_modules\@deepseek-ai\dsh\package.json"
  if (Test-Path $pkg) {
    try { return (Get-Content $pkg -Raw | ConvertFrom-Json).version } catch { return "?" }
  }
  return "(none)"
}

function Install-Tarball($name, $version, $destDir) {
  $enc = $name.Replace("/", "%2F")
  $meta = Invoke-RestMethod "https://registry.npmmirror.com/$enc" -TimeoutSec 30
  $url = $meta.versions.$version.dist.tarball
  $tmp = Join-Path $env:TEMP ("pkg-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Invoke-WebRequest $url -OutFile (Join-Path $tmp "pkg.tgz") -UseBasicParsing -TimeoutSec 180
  tar -xzf (Join-Path $tmp "pkg.tgz") -C $tmp
  $target = Join-Path $app "node_modules" ($destDir -replace '/', '\')
  if (Test-Path $target) { Remove-Item $target -Recurse -Force }
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Copy-Item (Join-Path $tmp "package\*") $target -Recurse -Force
  Remove-Item $tmp -Recurse -Force
  Write-Host "  ia32: $name@$version"
}

# 1. current version
$oldVer = Read-DshVersion $app
Write-Host "==> current DSH version: $oldVer"
Write-Host "==> target DSH version: $Version"

# 2. backup data
$data = Join-Path $Root "data"
if ((Test-Path $data) -and (Get-ChildItem $data -Force | Measure-Object).Count -gt 0) {
  $ts  = Get-Date -Format "yyyyMMdd-HHmmss"
  $bak = Join-Path $Root "data-backup-$ts"
  Copy-Item $data $bak -Recurse -Force
  Write-Host "==> data backed up to: $bak"
} else {
  Write-Host "==> no data to back up"
}

# 3. rebuild app from scratch
if (Test-Path $app) { Remove-Item $app -Recurse -Force }
New-Item -ItemType Directory -Path $app | Out-Null
[System.IO.File]::WriteAllText(
  (Join-Path $app "pnpm-workspace.yaml"),
  "nodeLinker: hoisted`n",
  (New-Object System.Text.UTF8Encoding $false)
)

# 4. install kernel with pnpm (fast + auto peer deps)
Write-Host "==> pnpm install @deepseek-ai/dsh@$Version ..."
& $pnpm add --dir $app "@deepseek-ai/dsh@$Version" --ignore-scripts --registry=https://registry.npmmirror.com 2>&1 | Select-Object -Last 5
if ($LASTEXITCODE -ne 0) { throw "pnpm install failed" }

# 5. ia32 native modules (npm/pnpm only install x64 platform packages on x64)
Write-Host "==> adding ia32 native modules ..."
Install-Tarball "@koromix/koffi-win32-ia32" $KoffiIa32 "@koromix/koffi-win32-ia32"
Install-Tarball "@img/sharp-win32-ia32" $SharpIa32 "@img/sharp-win32-ia32"
Install-Tarball "node-addon-require-builtin-win32-ia32-msvc" $RequireBuiltinIa32 "node-addon-require-builtin-win32-ia32-msvc"

# 6. apply ia32 compat patches (idempotent)
Write-Host "==> applying patches ..."
$nodeBin = Join-Path $Root "node\win-x64\node.exe"
if (Test-Path $nodeBin) {
  & $nodeBin (Join-Path $Root "patches\apply-patches.js") $app
} else {
  & node (Join-Path $Root "patches\apply-patches.js") $app
}
if ($LASTEXITCODE -ne 0) { throw "patch application failed" }

# 7. verify
$bin = Join-Path $app "node_modules\@deepseek-ai\dsh\lib\bin.js"
if (-not (Test-Path $bin)) { throw "after upgrade, bin.js is missing" }
$newVer = Read-DshVersion $app
Write-Host ("==> upgrade complete: {0} -> {1}" -f $oldVer, $newVer)
Write-Host "==> old data is in data-backup-*; rename it back to 'data' to roll back"
