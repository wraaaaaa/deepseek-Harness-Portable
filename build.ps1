# ============================================================
#  DSH Portable - one-shot build script (source repo -> full portable folder + Release zip)
# ============================================================
#  It rebuilds the whole portable bundle from scratch:
#    1) pnpm standalone (also used to install the kernel)
#    2) DSH kernel via pnpm (hoisted flat layout; npm's arborist hangs on DSH)
#    3) ia32 native modules (pnpm on x64 only installs x64 platform packages)
#    4) two minimal "ia32-only" compat patches (x64 behavior unchanged, see patches/)
#    5) Node.js (both archs), Electron
#    6) assemble click-to-run folder, optionally package the Release zip
#
#  Usage: powershell -File build.ps1 [-SkipDownloads] [-Zip]
#   -SkipDownloads : skip download/install (app/node/electron/tools must already exist)
#   -Zip           : also produce dist/DSH-Portable-<ReleaseVersion>.zip
#
#  Pinned versions (tested):
#     DSH       @deepseek-ai/dsh@0.1.1-rc.2
#     Node x64  v24.19.0 (win-x64)
#     Node x86  v22.23.0 (win-x86)
#     Electron  v43.4.1  (win32-x64)
#     pnpm      @pnpm/exe 11.22.0 (standalone pnpm.exe)

param(
  [string]$DshVersion   = "0.1.1-rc.2",
  [string]$NodeX64      = "v24.19.0",
  [string]$NodeX86      = "v22.23.0",
  [string]$Electron     = "v43.4.1",
  [string]$KoffiIa32    = "3.1.6",
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

function Install-Tarball($name, $version, $destDir) {
  $enc = $name.Replace("/", "%2F")
  $meta = Invoke-RestMethod "https://registry.npmmirror.com/$enc" -TimeoutSec 30
  $url = $meta.versions.$version.dist.tarball
  $tmp = Join-Path $env:TEMP ("pkg-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Invoke-WebRequest $url -OutFile (Join-Path $tmp "pkg.tgz") -UseBasicParsing -TimeoutSec 180
  tar -xzf (Join-Path $tmp "pkg.tgz") -C $tmp
  $target = Join-Path $Root "app\node_modules" ($destDir -replace '/', '\')
  if (Test-Path $target) { Remove-Item $target -Recurse -Force }
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Copy-Item (Join-Path $tmp "package\*") $target -Recurse -Force
  Remove-Item $tmp -Recurse -Force
  Write-Host "      ia32: $name@$version"
}

Write-Host "==> DSH Portable build (root: $Root)"

# ---- 1. pnpm standalone (bootstrap, needed by kernel install) ------------
Write-Host "==> 1/7 pnpm standalone"
if (-not (Test-Path (Join-Path $Root "tools\pnpm.exe"))) {
  if ($SkipDownloads) { throw "missing tools/pnpm.exe" }
  $tools = Join-Path $Root "tools"
  New-Dir $tools
  npm install @pnpm/exe --prefix $tools --registry=https://registry.npmmirror.com --no-audit --no-fund
  Copy-Item (Join-Path $tools "node_modules\@pnpm\exe\dist") (Join-Path $tools "dist") -Recurse -Force
  Copy-Item (Join-Path $tools "node_modules\@pnpm\exe\pnpm.exe") (Join-Path $tools "pnpm.exe") -Force
  Remove-Item (Join-Path $tools "node_modules") -Recurse -Force
  Remove-Item (Join-Path $tools "package.json"),(Join-Path $tools "package-lock.json") -Force -ErrorAction SilentlyContinue
} else {
  Write-Host "      pnpm already present"
}

# ---- 2. DSH kernel (pnpm + hoisted flat layout) --------------------------
Write-Host "==> 2/7 DSH kernel @deepseek-ai/dsh@$DshVersion"
if (-not (Test-Path (Join-Path $Root "app\node_modules\@deepseek-ai\dsh\lib\bin.js"))) {
  if ($SkipDownloads) { throw "app/ kernel missing (-SkipDownloads and not pre-placed)" }
  New-Dir (Join-Path $Root "app")
  [System.IO.File]::WriteAllText(
    (Join-Path $Root "app\pnpm-workspace.yaml"),
    "nodeLinker: hoisted`n",
    (New-Object System.Text.UTF8Encoding $false)
  )
  & (Join-Path $Root "tools\pnpm.exe") add --dir (Join-Path $Root "app") "@deepseek-ai/dsh@$DshVersion" --ignore-scripts --registry=https://registry.npmmirror.com
  if ($LASTEXITCODE -ne 0) { throw "pnpm install failed" }
  # ia32 native modules (pnpm only installs x64 platform packages on x64)
  Install-Tarball "@koromix/koffi-win32-ia32" $KoffiIa32 "@koromix/koffi-win32-ia32"
  Install-Tarball "@img/sharp-win32-ia32" $SharpIa32 "@img/sharp-win32-ia32"
  Install-Tarball "node-addon-require-builtin-win32-ia32-msvc" $RequireBuiltinIa32 "node-addon-require-builtin-win32-ia32-msvc"
} else {
  Write-Host "      kernel already present, skipping install"
}

# ---- 3. kernel patches (ia32-only; x64 behavior unchanged) ---------------
Write-Host "==> 3/7 apply kernel patches (idempotent)"
$nodeBin = Join-Path $Root "node\win-x64\node.exe"
if (Test-Path $nodeBin) {
  & $nodeBin (Join-Path $Root "patches\apply-patches.js") (Join-Path $Root "app")
} else {
  & node (Join-Path $Root "patches\apply-patches.js") (Join-Path $Root "app")
}
if ($LASTEXITCODE -ne 0) { throw "patch application failed" }

# ---- 4. Node.js runtimes (keep node.exe only) ----------------------------
Write-Host "==> 4/7 Node.js $NodeX64 (x64) / $NodeX86 (x86)"
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

# ---- 5. Electron (x64 window shell) --------------------------------------
Write-Host "==> 5/7 Electron $Electron"
if (-not (Test-Path (Join-Path $Root "electron\electron.exe"))) {
  if ($SkipDownloads) { throw "missing electron/electron.exe" }
  $zip = Join-Path $env:TEMP "electron-$Electron-win32-x64.zip"
  curl.exe -L --retry 5 --retry-delay 3 -o $zip "https://npmmirror.com/mirrors/electron/$($Electron.TrimStart('v'))/electron-$Electron-win32-x64.zip"
  if ($LASTEXITCODE -ne 0) { throw "electron download failed" }
  Expand-Archive $zip -DestinationPath (Join-Path $Root "electron") -Force
  Remove-Item $zip
}

# ---- 6. data/ skeleton + verify ------------------------------------------
Write-Host "==> 6/7 data/ skeleton and verify"
New-Dir (Join-Path $Root "data")
foreach ($p in @(
  "app\node_modules\@deepseek-ai\dsh\lib\bin.js",
  "node\win-x64\node.exe", "node\win-x86\node.exe",
  "electron\electron.exe", "shell\server-boot.js",
  "tools\pnpm.exe"
)) { if (-not (Test-Path (Join-Path $Root $p))) { throw "missing after build: $p" } }

$tot = (Get-ChildItem $Root -Recurse -File | Where-Object { $_.FullName -notmatch '\\.git\\|\data\\' } | Measure-Object Length -Sum).Sum
Write-Host ("==> build complete (portable folder ~ {0:N0} MB)" -f ($tot/1MB))

# ---- 7. optional: package Release zip ------------------------------------
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
