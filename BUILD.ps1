# Hydride 构建脚本：读取版本号 → 构建 Rust 项目 → 编译 Inno 安装包
# 用法: .\BUILD.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$Iscc = "C:\Program Files\Inno Setup 7\ISCC.exe"

# 1. 从 Cargo.toml 读取版本号
$cargo = Get-Content "$ProjectRoot\rust\Cargo.toml"
$version = ($cargo | Select-String '^version = ".*"').Line -replace 'version = "|"', ''
Write-Host "Version: $version" -ForegroundColor Cyan

# 2. 构建 Rust 项目
Write-Host "Building project..." -ForegroundColor Yellow
cargo build --release --manifest-path "$ProjectRoot\rust\Cargo.toml"
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

# 3. 复制产物到 publish（installer.iss 的 Source 相对 rust 目录）
Write-Host "Copying artifact..." -ForegroundColor Yellow
$publishDir = "$ProjectRoot\rust\publish"
New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
Copy-Item "$ProjectRoot\rust\target\release\hydride_svc64.exe" "$publishDir\hydride_svc64.exe" -Force

# 4. 更新 rust\installer.iss 中的版本号
Write-Host "Updating installer.iss..." -ForegroundColor Yellow
$iss = Get-Content "$ProjectRoot\rust\installer.iss" -Raw -Encoding UTF8
$iss = $iss -replace '#define MyAppVersion ".*"', "#define MyAppVersion `"$version`""
[System.IO.File]::WriteAllText("$ProjectRoot\rust\installer.iss", $iss, [System.Text.UTF8Encoding]::new($true))

# 5. 编译 Inno 安装包
Write-Host "Compiling installer..." -ForegroundColor Yellow
& $Iscc "$ProjectRoot\rust\installer.iss"
if ($LASTEXITCODE -ne 0) { throw "Installer build failed" }

Write-Host "Done: rust\publish\hydride-svc-win-x64-setup-v$version.exe" -ForegroundColor Green
