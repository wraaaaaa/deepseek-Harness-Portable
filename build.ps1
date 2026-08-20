# ============================================================
#  DSH Portable - one-shot build script (source repo -> full portable folder + Release zip)
# ============================================================
#  Why this script exists: see README "Why source in repo, binaries in Release".
#  It rebuilds the whole portable bundle from scratch:
#    1) npm-install the OFFICIAL DSH kernel (@deepseek-ai/dsh, untouched)
#    2) add the 32-bit native modules (npm on x64 only installs x64 platform packages)
#    3) apply the two minimal "ia32-only" compat patches (x64 behavior unchanged, see patches/)
#    4) download Node.js (both archs), Electron, and standalone pnpm
#    5) assemble the click-to-run folder and package the Release zip
#
#  Usage: powershell -File build.ps1 [-SkipDownloads] [-Zip]
#   -SkipDownloads : skip download/install (app/node/electron/tools must already exist)
#   -Zip           : also produce dist/DSH-Portable-<ReleaseVersion>.zip (for GitHub Release)
#
#  Pinned versions (tested):
#     DSH       @deepseek-ai/dsh@0.1.0-rc.7
#     Node x64  v24.19.0 (win-x64)
#     Node x86  v22.23.0 (win-x86)
#     Electron  v43.4.1  (win32-x64)
#     pnpm      @pnpm/exe 11.22.0 (standalone pnpm.exe)

param(
  [string]$DshVersion   = "0.1.0-rc.7",
  [string]$NodeX64      = "v24.19.0",
  [string]$NodeX86      = "v22.23.0",
  [string]$Electron     = "v43.4.1",
  [string]$KoffiIa32    = "3.1.5",
  [string]$SharpIa32    = "0.35.3",
  [string]$RequireBuiltinIa32 = "0.1.5",
  [string]$ReleaseVersion = "v1.0",
  [switch]$SkipDownloads,
  [switch]$Zip
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path   # repo root (= portable root)
$Dist = Join-Path $Root "dist"

function New-Dir($p) { New-Item -ItemType Directory -Path $p -Force | Out-Null }

Write-Host "==> DSH Portable build (root: $Root)"

# ---- 1. DSH kernel (stock npm install) ----------------------------------
Write-Host "==> 1/6 DSH kernel @deepseek-ai/dsh@$DshVersion"
if (-not (Test-Path (Join-Path $Root "app\node_modules\@deepseek-ai\dsh\lib\bin.js"))) {
  if ($SkipDownloads) { throw "app/ kernel missing (-SkipDownloads and not pre-placed)" }
  New-Dir (Join-Path $Root "app")
  npm install --prefix (Join-Path $Root "app") --no-audit --no-fund "@deepseek-ai/dsh@$DshVersion"
  # npm on x64 only installs x64 platform packages; add the ia32 native modules explicitly
  npm install --prefix (Join-Path $Root "app") --no-save --no-audit --no-fund `
    "@koromix/koffi-win32-ia32@$KoffiIa32" `
    "@img/sharp-win32-ia32@$SharpIa32" `
    "node-addon-require-builtin-win32-ia32-msvc@$RequireBuiltinIa32"
} else {
  Write-Host "      kernel already present, skipping npm install"
}

# ---- 2. kernel patches (ia32-only; x64 behavior unchanged) --------------
Write-Host "==> 2/6 apply kernel patches (idempotent)"
$nodeBin = Join-Path $Root "node\win-x64\node.exe"
if (Test-Path $nodeBin) {
  & $nodeBin (Join-Path $Root "patches\apply-patches.js") (Join-Path $Root "app")
} else {
  & node (Join-Path $Root "patches\apply-patches.js") (Join-Path $Root "app")
}
if ($LASTEXITCODE -ne 0) { throw "patch application failed" }

# ---- 3. Node.js runtimes (keep node.exe only) ---------------------------
Write-Host "==> 3/6 Node.js $NodeX64 (x64) / $NodeX86 (x86)"
foreach ($pair in @(@($NodeX64, "win-x64"), @($NodeX86, "win-x86"))) {
  $ver = $pair[0]; $arch = $pair[1]
  $exe = Join-Path $Root "node\$arch\node.exe"
  if (-not (Test-Path $exe)) {
    if ($SkipDownloads) { throw "missing $exe" }
    $zip = Join-Path $env:TEMP "node-$ver-$arch.zip"
    Invoke-WebRequest "https://nodejs.org/dist/$ver/node-$ver-$arch.zip" -OutFile $zip -UseBasicParsing
    $tmpX = Join-Path $env:TEMP "node-x-$arch"
    if (Test-Path $tmpX) { Remove-Item $tmpX -Recurse -Force }
    Expand-Archive $zip -DestinationPath $tmpX -Force
    Remove-Item $zip
    New-Dir (Join-Path $Root "node\$arch")
    Copy-Item (Join-Path $tmpX "node-$ver-$arch\node.exe") $exe -Force
    Remove-Item $tmpX -Recurse -Force
  }
  Get-ChildItem (Split-Path $exe) | Where-Object { $_.Name -ne 'node.exe' } | Remove-Item -Recurse -Force
}

# ---- 4. Electron (x64 window shell) -------------------------------------
Write-Host "==> 4/6 Electron $Electron"
if (-not (Test-Path (Join-Path $Root "electron\electron.exe"))) {
  if ($SkipDownloads) { throw "missing electron/electron.exe" }
  $zip = Join-Path $env:TEMP "electron-$Electron-win32-x64.zip"
  curl.exe -L --retry 5 --retry-delay 3 -o $zip "https://npmmirror.com/mirrors/electron/$($Electron.TrimStart('v'))/electron-$Electron-win32-x64.zip"
  if ($LASTEXITCODE -ne 0) { throw "electron download failed" }
  Expand-Archive $zip -DestinationPath (Join-Path $Root "electron") -Force
  Remove-Item $zip
}

# ---- 5. pnpm (standalone exe + dist, for plugin install) ----------------
Write-Host "==> 5/6 pnpm standalone"
if (-not (Test-Path (Join-Path $Root "tools\pnpm.exe"))) {
  if ($SkipDownloads) { throw "missing tools/pnpm.exe" }
  $tools = Join-Path $Root "tools"
  New-Dir $tools
  npm install @pnpm/exe --prefix $tools --registry=https://registry.npmmirror.com --no-audit --no-fund
  Copy-Item (Join-Path $tools "node_modules\@pnpm\exe\dist") (Join-Path $tools "dist") -Recurse -Force
  Copy-Item (Join-Path $tools "node_modules\@pnpm\exe\pnpm.exe") (Join-Path $tools "pnpm.exe") -Force
  Remove-Item (Join-Path $tools "node_modules") -Recurse -Force
  Remove-Item (Join-Path $tools "package.json"),(Join-Path $tools "package-lock.json") -Force -ErrorAction SilentlyContinue
}

# ---- 6. data/ skeleton + verify -----------------------------------------
Write-Host "==> 6/6 data/ skeleton and verify"
New-Dir (Join-Path $Root "data")
foreach ($p in @(
  "app\node_modules\@deepseek-ai\dsh\lib\bin.js",
  "node\win-x64\node.exe", "node\win-x86\node.exe",
  "electron\electron.exe", "shell\server-boot.js",
  "tools\pnpm.exe"
)) { if (-not (Test-Path (Join-Path $Root $p))) { throw "missing after build: $p" } }

$tot = (Get-ChildItem $Root -Recurse -File | Where-Object { $_.FullName -notmatch '\\.git\\|\data\\' } | Measure-Object Length -Sum).Sum
Write-Host ("==> build complete (portable folder ~ {0:N0} MB)" -f ($tot/1MB))

# ---- optional: package Release zip --------------------------------------
if ($Zip) {
  New-Dir $Dist
  $zipPath = Join-Path $Dist "DSH-Portable-$ReleaseVersion.zip"
  if (Test-Path $zipPath) { Remove-Item $zipPath }
  Write-Host "==> packaging Release zip (takes a few minutes)..."
  # exclude .git / data / dist
  tar.exe -a -c -f $zipPath `
    --exclude ".git" --exclude "data" --exclude "dist" `
    -C $Root .
  Write-Host ("==> zip written: $zipPath ({0:N0} MB)" -f ((Get-Item $zipPath).Length/1MB))
}
