# 安全

## 报告问题

发现安全问题请不要开公开 issue。发邮件到维护者（见仓库提交记录），写清复现步骤、影响版本与可能的利用方式。确认后会在修复版本里署名。

## 密钥

- AI API key 三层来源：环境变量 → Release 钥匙串 → Debug 的 `~/Library/Application Support/Causality/credentials.plist`（目录 0700、文件 0600）。都不进工程包、不进仓库。
- `.causal` 工程包只含故事数据与本地相对路径的配图，不含凭据。
- 提 issue / PR 前检查日志与截图里没有 key、token 与个人路径。

## 支持范围

当前为 0.x 预览版，只保证最新提交的 Debug 构建；发布版以带签名的 Release 为准。
