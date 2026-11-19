[English](CONTRIBUTING.md) · **简体中文**

# 参与开发

因果是 macOS 上的 SwiftUI App + 一个独立的模型层 Swift Package。改动尽量按「模型层 → 命令行 → 界面」的顺序落，模型层的测试是唯一的硬门槛。

## 环境

- macOS 15+、Xcode 16+
- `xcodegen`（`brew install xcodegen`）
- 不需要开发者证书：Debug 默认 ad-hoc 签名

## 跑一遍

```bash
./scripts/check.sh            # swift test + CLI 自检 + xcodegen + 构建 + App 测试
cd Packages/CausalityCore && swift test
cd Packages/CausalityCore && swift run causal bench
```

改了 `project.yml` 或新增了 `Sources/Causality/**` 下的文件，先 `xcodegen generate` 再构建；`check.sh` 会代跑。

## 写法

- 注释用中文，解释「为什么」；命名与现有代码保持一致。
- 模型层保持 Foundation + Observation，不引入 SwiftUI。
- 所有工程改动走 `EditOperation`，一笔撤销；不要把数组直接改掉。
- 新的 schema 字段一律可选、解码缺省，旧包要能打开；写盘统一写当前 `schemaVersion`。
- 新规则先写模型层测试，再写 CLI 断言（`scripts/check.sh`），最后接界面。
- 保存、切换工程这类跨 `await` 的顺序，写到 `Tests/CausalityAppTests`：用 `SaveQueue.setBeforeSave` 的写盘闸门控制时序，不靠 sleep。
- 不把 API key、证书、个人路径写进仓库；`Config/Local.xcconfig` 已被忽略。

## 提交

一条提交只做一件事，信息写清「改了什么、为什么」。测试与 CLI 自检通过后再提交。

## 凭据与网络

- AI key 走环境变量（`CAUSAL_*_KEY`）、Release 钥匙串或 Debug 的 0600 `credentials.plist`。
- 模型层测试不联网。
- 公证时先关系统代理，否则 `codesign` 取时间戳可能 502；`scripts/release.sh` 会预检。
