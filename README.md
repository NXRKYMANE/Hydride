# 🧠 Hydride System Memory Manager Service

Hydride System Memory Manager Service — 轻量高性能的 Windows 系统内存管理服务，定期清理进程工作集以降低物理内存压力。

使用高性能 **C#** 开发，基于 **.NET 10**，通过 **NativeAOT** 编译为单个原生二进制文件 — 目标机器无需安装 .NET 运行时。

> 本项目基于旧版 **PCL2**（Plain Craft Launcher 2，作者 **龙腾猫跃**）封装构建，将其核心内存清理引擎重新打包为具有动态调度和自动清理功能的长期运行服务。

## ⚙️ 工作原理

1. 启动时将 `libs/LIBPCL2.dll`（base64）解码为 `hsmmts.exe`，放到 `%WINDIR%\Temp\HSMM`。
2. 每 60 秒一个周期，按内存使用率分 5 档调整清理频率（每 20% 一档）：使用率越高，清理越频繁（每分钟 1~5 次）。
3. 每次清理运行一次 `hsmmts.exe --memory`，对比清理前后内存，任务均匀分布在整个周期内。
4. 退出时强制终止所有 `hsmmts` 进程并删除 `%WINDIR%\Temp\HSMM`。

## 📁 项目结构

```
Hydride/
├── csharp/                          # C# 服务源码与构建
│   ├── ServiceCore.cs               # 主程序（内存监控 + 动态清理调度，顶层语句入口）
│   ├── Hydride.csproj               # 项目文件（.NET 10 / NativeAOT / 单文件发布）
│   ├── installer.iss                # Inno Setup 安装脚本
│   └── publish/                     # 构建产物（发布 exe 与安装包）
├── misc/                            # 资源文件
│   ├── Background.bmp / .png        # 安装向导左侧背景图（源图 + 位图）
│   ├── Csharp.bmp / .png            # 安装向导右上角小图（源图 + 位图）
│   ├── Proj.ico                     # 安装包与程序图标
│   └── Proj.png                     # 图标源图
├── docs/                            # 网页版文档
│   ├── README_CN.html
│   └── README_EN.html
├── libs/
│   └── LIBPCL2.dll                  # 内存清理引擎（base64 封装，运行时解码为 hsmmts.exe）
├── .github/                         # Issue / PR 模板
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
├── app.manifest                     # UAC 管理员权限清单
├── BUILD.ps1                        # 一键构建脚本（编译 → 发布 → 打包）
├── .gitattributes                   # Git 语言统计排除（安装脚本 / 周边脚本）
├── AGENTS.md                        # 项目规则（AI 协作约定）
├── CODE_OF_CONDUCT.md               # 行为准则
├── CONTRIBUTING.md                  # 贡献指南
├── LICENSE
├── README.md / README_EN.md
└── SECURITY.md                      # 安全政策
```

## 📋 运行要求

**运行：**
- Windows 10 / 11（或等效的 Windows Server）
- 管理员权限（已包含 UAC 清单）
- [Silanes](https://github.com/NXRKYMANE/Silanes) — 前置框架，用于将 Hydride 注册为 Windows 系统服务

**构建：**
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- Visual Studio 2022+ 或 Build Tools（含 "使用 C++ 的桌面开发" 工作负载）
- Inno Setup 7（仅打包时需要）

## 🛠️ 构建

在 **VS 开发者命令提示符**（或已加载 VS 环境的 PowerShell）中执行：

```bash
dotnet build
```

发布产物为单个原生可执行文件：`hydride_svc64.exe`（NativeAOT，无运行时依赖）。

## 📦 Inno Setup 安装包

构建安装包：

```bash
# 1. 先构建项目（如上）
# 2. 安装 Inno Setup（https://jrsoftware.org/isdl.php）
# 3. 编译安装包
ISCC.exe csharp\installer.iss
```

输出：`csharp\publish\hydride-svc-win-x64-setup-v1.3.0.exe`。

安装包特性：
- 中英文双语界面，默认跟随系统语言
- 智能版本比较：升级静默、同版本询问重装、降级警告
- 安装 `hydride_svc64.exe`、`libs/` 与文档，写入服务 YAML 配置
- 通过 Silanes 注册并启动服务，全程退出码检查（失败弹「终止 / 重试 / 忽略」）
- 静默模式（`/S`）下自动等待旧进程退出
- 卸载时通过 Silanes 删除服务并移除所有文件

> **Silanes 集成要点：** YAML 无需转义路径；从注册表 `HKLM\...\App Paths\silanes64.exe` 定位 silanes；失败时用 `ExecAndCaptureOutput` 捕获退出码并弹「终止 / 重试 / 忽略」。

## 🚀 部署

使用 [Releases](https://github.com/NXRKYMANE/Hydride/releases) 的安装包即可完整安装并自动注册服务。

手动部署：
1. 将 `csharp/publish/` 中的 `hydride_svc64.exe` 复制到目标机器。
2. 将 `libs/LIBPCL2.dll` 与 exe 放同一目录。
3. 安装 [Silanes](https://github.com/NXRKYMANE/Silanes)（自动注册 `silanes64.exe` 到 PATH）。
4. 注册服务：`silanes64.exe -m --install libs\hydride_svc64.yaml`
5. 启动服务：`silanes64.exe -m --start hydride_svc64`

## ⚠️ 免责声明

**本项目本质上只是一个比较鸡肋的工具，无法保证对所有计算机有效。建议先下载 PCL2 启动器测试其内存清理功能并留意副作用；若无明显效果甚至加重负担，请立即卸载本服务。**

## 💖 赞助

如果这个项目对你有帮助，欢迎[赞助支持](https://ifdian.net/a/NXRKYMANE) 。

## 📄 许可证

Copyright © 2026 NXRKYMANE SOFTWARE
