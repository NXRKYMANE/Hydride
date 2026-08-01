# WinSKG 构建脚本
# ---------------------
# 从 WinSKG.csproj 读取版本号，构建项目，
# 并编译 NSIS 安装包。
# 用法: .\BUILD.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

# 1. 从 csproj 读取版本号
$csproj = [xml](Get-Content "$ProjectRoot\WinSKG.csproj")
$version = $csproj.Project.PropertyGroup.Version
Write-Host "Version: $version" -ForegroundColor Cyan

# 2. 构建项目
Write-Host "Building project..." -ForegroundColor Yellow
dotnet build "$ProjectRoot\WinSKG.csproj"
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

# 3. 更新 deployment.nsi 中的版本号
Write-Host "Updating deployment.nsi..." -ForegroundColor Yellow
$nsi = Get-Content "$ProjectRoot\deployment.nsi" -Raw -Encoding UTF8
$nsi = $nsi -replace '!define PRODUCT_VERSION ".*"', "!define PRODUCT_VERSION `"$version`""
[System.IO.File]::WriteAllText("$ProjectRoot\deployment.nsi", $nsi, [System.Text.UTF8Encoding]::new($true))

# 4. 编译 NSIS 安装包
Write-Host "Compiling installer..." -ForegroundColor Yellow
& "C:\Program Files (x86)\NSIS\makensis.exe" "$ProjectRoot\deployment.nsi"
if ($LASTEXITCODE -ne 0) { throw "Installer build failed" }

Write-Host "Done: publish\winskg-x64-setup-v$version.exe" -ForegroundColor Green
