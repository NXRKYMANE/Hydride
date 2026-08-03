# 安全政策

## 支持范围

以下版本接受安全更新与漏洞报告：

- 最新的正式发布版本（v1.2.x）

## 报告漏洞

请**不要**在公开渠道（Issue / 讨论 / PR）披露安全漏洞。请通过以下方式私下报告：

- GitHub Security Advisory：仓库页面 → **Security → Report a vulnerability**
- 维护者邮箱（NXRKYMANE）

请提供：

- 受影响版本
- 漏洞描述与影响
- 复现步骤（如可能）
- 建议的修复方案（可选）

## 处理流程

- 收到报告后 72 小时内确认
- 确认后尽快修复并发布补丁版本
- 修复发布前不会公开漏洞细节

## 安全设计

- 服务由 Silanes 注册并以 LocalSystem 权限运行，仅执行内存清理，无网络监听
- 单实例互斥：`Global\Hydride_HSMM_SingleInstance` 防止多实例争用同一临时目录
- 退出时精准终止本实例创建的子进程（记录 PID 并校验进程名），避免误杀系统中同名进程
- 清理引擎 `hsmmts.exe` 以隐藏窗口方式运行，工作目录为 `%WINDIR%\Temp\HSMM`，退出时整目录删除
- NativeAOT 单文件发布，无运行时依赖，降低供应链面
