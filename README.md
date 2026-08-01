# 🧠 Hydride System Memory Manager Service

Hydride System Memory Manager Service — 轻量高性能的 Windows 系统内存管理服务，定期清理进程工作集以降低物理内存压力。

使用高性能 **C#** 开发，基于 **.NET 10**，通过 **NativeAOT** 编译为单个原生二进制文件 — 目标机器无需安装 .NET 运行时。

> 本项目基于旧版 **PCL2**（Plain Craft Launcher 2，作者 **龙腾猫跃**）封装构建，将其核心内存清理引擎重新打包为具有动态调度和自动清理功能的长期运行服务。

## ⚙️ 工作原理

1. 启动时，将 `libs/LIBPCL2.dll`（base64 编码）解码为 `hsmmts.exe`，放置到 `%WINDIR%\Temp\HSMM` 下。
2. 进入 60 秒循环，根据当前内存使用率在 8 个档位间动态调整清理频率（每 12.5% 一档）：
   - **0–12.5%** → 每分钟 1 次
   - **12.5–25%** → 每分钟 2 次
   - **25–37.5%** → 每分钟 3 次
   - **37.5–50%** → 每分钟 4 次
   - **50–62.5%** → 每分钟 5 次
   - **62.5–75%** → 每分钟 6 次
   - **75–87.5%** → 每分钟 7 次
   - **87.5–100%** → 每分钟 8 次
3. 每次清理运行一次 `hsmmts.exe --memory`，对比清理前后的内存使用量，清理均匀分布在整个周期内。
4. 退出时，强制终止所有 `hsmmts` 进程并删除 `%WINDIR%\Temp\HSMM`。

## 📋 运行要求

**运行：**
- Windows 10 / 11（或等效的 Windows Server）
- 管理员权限（已包含 UAC 清单）
- [Silanes](https://github.com/NXRKYMANE/Silanes) — 前置框架，用于将 Hydride 注册为 Windows 系统服务

**构建：**
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- Visual Studio 2022+，安装 "使用 C++ 的桌面开发" 工作负载（MSVC 工具链 + Windows SDK）
- 或安装 Visual Studio Build Tools 并包含相同组件
- NSIS 3.x（仅构建安装包时需要）

## 🛠️ 构建

在 **VS 开发者命令提示符**（或已加载 VS 环境的 PowerShell）中执行：

```bash
dotnet build
```

发布产物为单个原生可执行文件：
- `hydride_svc64.exe` — 独立原生二进制文件（NativeAOT），无运行时依赖

## 📦 NSIS 安装包

构建安装包：

```bash
# 1. 先构建项目（如上）
# 2. 安装 NSIS（https://nsis.sourceforge.io/Download）
# 3. 编译安装包
makensis deployment.nsi
```

输出：`publish\hydride-svc-win-x64-setup-v${PRODUCT_VERSION}.exe`（当前版本 v1.0.0）。

安装包特性：
- 中英文双语界面，首次安装弹语言选择框，自动记忆选择
- 智能版本比较：升级静默执行、同版本询问重装、旧版本降级警告
- 将 `hydride_svc64.exe`、`libs/` 和文档安装到所选目录
- 写入包含正确安装路径的服务 YAML 配置
- 通过 Silanes 注册并启动 Windows 服务，全程退出码检查（失败弹「终止 / 重试 / 忽略」）
- 静默模式（`/S`）下自动等待旧进程退出，避免覆盖运行中的 exe
- 自定义图标与向导位图，安装包附带完整版本元数据
- 卸载时通过 Silanes 删除服务，然后移除所有文件

> **Silanes 集成注意事项：**
> 1. **YAML 路径处理** — YAML 对不加引号的值原生支持反斜杠（如 `C:\Program Files\...`），无需转义或替换，直接书写路径即可。
> 2. **Silanes 路径查找** — 安装器进程中 `silanes64.exe` 可能不在 PATH 中。从注册表 `HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\silanes64.exe` 读取完整路径。
> 3. **退出码检查** — 使用 `nsExec::ExecToStack` 捕获命令输出与退出码，注册 / 启动 / 删除服务失败时弹「终止 / 重试 / 忽略」对话框，避免静默失败。
> 4. **NSIS 变量展开** — NSIS 单引号字符串不展开变量，必须使用双引号。

## 🚀 部署

使用 [Releases](https://github.com/NXRKYMANE/Hydride/releases) 页面提供的 NSIS 安装包可实现完整安装和自动服务注册。

手动部署：
1. 将 `publish/` 目录中的 `hydride_svc64.exe` 复制到目标机器。
2. 将 `libs/LIBPCL2.dll` 放置在与 `hydride_svc64.exe` 相同的目录下。
3. 确保已安装 [Silanes](https://github.com/NXRKYMANE/Silanes)（会自动注册 `silanes64.exe` 到系统 PATH）。
4. 注册服务：`silanes64.exe -m --install libs\hydride_svc64.yaml`
5. 启动服务：`silanes64.exe -m --start hydride_svc64`

## ⚠️ 免责声明

**本项目本质上只是一个比较鸡肋的工具。我无法保证本服务对所有计算机都有效。强烈建议你先下载 PCL2 启动器，测试其内置的内存清理功能（启动器内部也有对该功能的说明），看看是否存在任何副作用。如果没有明显效果甚至导致性能负担加重，请立即从计算机中移除本服务。**

## 📄 许可证

Copyright © 2026 NXRKYMANE SOFTWARE
