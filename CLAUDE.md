# 项目规则

## 注释
- 注释块不超过两行；单行注释过长时折叠为两行

## 代码质量（每次编辑后检查）
- 优化冗余代码，消除死代码
- 优先合并可合并的代码，合并后复查是否还能进一步删除
- 清理未使用的 use 导入（Rust）

代码部分始终注释使用中文记录，避免使用英文注释
每次对话完,整理claudemd文件,同时如果项目代码部分有重要变动请在claudemd中记录下来
每次推送代码到仓库时消息总结一个并且使用英文,建立新版本release资产时要和往期版本的格式一致,并且也使用英文

## 项目结构
- Project/：Rust 服务源码（main.rs / service_core.rs / build.rs / installer.iss / Cargo.toml）
- Libs/：LIBPCL2.dll（base64 文本封装，运行时解码为 hsmmts.exe）
- Misc/：图标与安装向导图片
- Publish/：构建产物（已被 gitignore）
- README.md（英文）+ README_CN.md（中文），首行互为语言切换链接

## 重要变动记录
- 2026-08-10：目录重构 rust→Project、libs→Libs、misc→Misc、publish→根目录 Publish；Docs 文件夹已删除
- 2026-08-10：服务配置由 YAML 迁移为 TOML（installer.iss 生成 hydride_svc64.toml，路径用单引号字面字符串）
- 2026-08-10：BUILD.ps1 固化工具链（无 VS 时自动配置 F:\DevTools\MSVC + Windows11 SDK，并自动探测 Inno Setup 6/7）
- 2026-08-10：版本升至 2.2.0；git 提交历史、GitHub Release 页面、GitHub 平台文件（CONTRIBUTING/SECURITY/.github 等）全部英文化；SECURITY.md 去除版本号
- 2026-08-10：发布 v2.2.0（提交 2035d33 + tag + Release，资产为安装包，说明英文，格式与往期一致）
- 2026-08-10：重写历史提交消息去除全部版本号（如 v3.6.2、.NET 10、v2.2.0）并强推；提交消息一律英文且不含版本号
- 2026-08-11：修复调度塌缩 bug——低内存档（PCL2 1 次/分）时周期循环任务瞬间完成即退出外层循环，导致每秒清理；现内层循环跑满 60s 周期，已完成引擎等待到周期结束
- 2026-08-11：清理频率调整——PCL2 引擎上限升至 5 次/分（每 25% 一档），Standby 固定 1 次/分；版本升至 2.3.0
- 2026-08-11：发布 v2.3.0（提交 dfe7f99 + tag + Release，资产为安装包，说明英文，格式与往期一致）
