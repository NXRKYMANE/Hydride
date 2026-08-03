# Hydride 构建脚本：读取版本号 → 构建项目 → 编译 Inno 安装包
# 用法: .\BUILD.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$Iscc = "C:\Program Files\Inno Setup 7\ISCC.exe"

# 1. 从 csproj 读取版本号
$csproj = [xml](Get-Content "$ProjectRoot\csharp\Hydride.csproj")
$version = $csproj.Project.PropertyGroup.Version
Write-Host "Version: $version" -ForegroundColor Cyan

# 2. 构建项目
Write-Host "Building project..." -ForegroundColor Yellow
dotnet build "$ProjectRoot\csharp\Hydride.csproj"
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

# 3. 更新 csharp\installer.iss 中的版本号
Write-Host "Updating installer.iss..." -ForegroundColor Yellow
$iss = Get-Content "$ProjectRoot\csharp\installer.iss" -Raw -Encoding UTF8
$iss = $iss -replace '#define MyAppVersion ".*"', "#define MyAppVersion `"$version`""
[System.IO.File]::WriteAllText("$ProjectRoot\csharp\installer.iss", $iss, [System.Text.UTF8Encoding]::new($true))

# 4. 编译 Inno 安装包
Write-Host "Compiling installer..." -ForegroundColor Yellow
& $Iscc "$ProjectRoot\csharp\installer.iss"
if ($LASTEXITCODE -ne 0) { throw "Installer build failed" }

Write-Host "Done: csharp\publish\hydride-svc-win-x64-setup-v$version.exe" -ForegroundColor Green
