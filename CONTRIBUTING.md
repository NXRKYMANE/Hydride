# 贡献指南

感谢你对 Hydride 的关注与贡献！

## 项目结构要点

- **单实现**：Rust（edition 2024）单一实现，产物为 `hydride_svc64.exe`（入口 `rust/main.rs`，核心逻辑 `rust/service_core.rs`）。
- **安装器**：Inno Setup 7 脚本位于 `rust/installer.iss`，由 `BUILD.ps1` 统一构建（编译 → 发布 → 打包）。
- **版本单一来源**：`rust/Cargo.toml` 的 `version`，`BUILD.ps1` 自动同步到 `installer.iss`。

## 开发流程

1. Fork 本仓库并创建功能分支
2. 修改代码
3. 本地验证：运行 `.\BUILD.ps1`（编译 + 打包，0 警告 0 错误）
4. 提交并创建 Pull Request

## 代码规范

- 注释不超过两行；单行注释过长时折叠为两行
- 每次编辑后检查：优化冗余 / 死代码，合并可合并的代码，清理未使用的 use（Rust）
- 修改安装器时注意：保持 [CustomMessages] 双语同步（english / chinesesimp）

## 提交信息

建议用清晰的中文或英文描述变更内容，例如"修复安装器日志框无法滚动到底部"。
