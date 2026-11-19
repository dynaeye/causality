import Foundation
import XCTest

@testable import Causality

/// 覆盖「工具 › 安装命令行工具」背后的复制逻辑，不依赖界面。
final class CLIToolTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIToolTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// 造一个和发布包同形状的 cli 目录。
    private func makeBundledCLI() throws -> URL {
        let source = root.appendingPathComponent("bundle/cli", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let binary = source.appendingPathComponent(CLITool.binaryName)
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let resource = source.appendingPathComponent(CLITool.resourceBundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: resource, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: resource.appendingPathComponent("Info.plist"))
        return source
    }

    func testInstallCopiesBinaryAndResourceBundle() throws {
        let source = try makeBundledCLI()
        let destination = root.appendingPathComponent("home/.local/bin", isDirectory: true)

        let installed = try CLITool.install(from: source, into: destination)

        XCTAssertEqual(installed.path, destination.appendingPathComponent(CLITool.binaryName).path)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installed.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent(CLITool.resourceBundleName).path
            ),
            "资源包必须一起装，只拷二进制会崩在 unable to find bundle"
        )
    }

    func testInstallIsIdempotent() throws {
        let source = try makeBundledCLI()
        let destination = root.appendingPathComponent("bin", isDirectory: true)
        _ = try CLITool.install(from: source, into: destination)
        _ = try CLITool.install(from: source, into: destination)
        let entries = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        XCTAssertEqual(entries, [CLITool.binaryName, CLITool.resourceBundleName].sorted())
    }

    func testInstallWithoutBundledCLIThrows() {
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true))
        XCTAssertThrowsError(try CLITool.install(from: empty, into: root.appendingPathComponent("bin"))) { error in
            XCTAssertTrue(error is CLITool.Failure)
        }
    }

    func testMCPConfigIsValidJSONWithCommandAndArgs() throws {
        let executable = URL(fileURLWithPath: "/Users/me/.local/bin/causal")
        let json = CLITool.mcpConfig(executable: executable)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: Any])
        let entry = try XCTUnwrap(servers["causality"] as? [String: Any])
        XCTAssertEqual(entry["command"] as? String, executable.path)
        XCTAssertEqual(entry["args"] as? [String], ["mcp"])
    }

    func testClientArgumentsUseOwnCLI() {
        let cli = URL(fileURLWithPath: "/Users/me/.local/bin/causal")
        XCTAssertEqual(
            CLIClient.codex.arguments(cli: cli),
            ["mcp", "add", "causality", "--", cli.path, "mcp"]
        )
        XCTAssertEqual(
            CLIClient.pi.arguments(cli: cli),
            ["mcp", "add", "causality", "--", cli.path, "mcp"]
        )
        XCTAssertEqual(
            CLIClient.hermes.arguments(cli: cli),
            ["mcp", "add", "causality", "--command", cli.path, "--args", "mcp"]
        )
    }

    func testMCPConfigSurvivesPathWithSpaceAndQuote() throws {
        let executable = URL(fileURLWithPath: "/Volumes/My Disk/因果\"cli\"/causal")
        let data = try XCTUnwrap(CLITool.mcpConfig(executable: executable).data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: Any])
        let entry = try XCTUnwrap(servers["causality"] as? [String: Any])
        XCTAssertEqual(entry["command"] as? String, executable.path)
    }
}

/// 桌面类客户端：App 自己改它的 JSON，写入形状必须对得上各自的规范。
final class ConfigClientTests: XCTestCase {
    private let cli = URL(fileURLWithPath: "/Users/someone/.local/bin/causal")

    func testEntriesMatchEachClientsSchema() throws {
        let command = "/Users/someone/.local/bin/causal"

        for client in [ConfigClient.claudeDesktop, .cursor, .windsurf, .kiro] {
            XCTAssertEqual(client.rootKey, "mcpServers", client.displayName)
            let entry = client.entry(cli: cli)
            XCTAssertEqual(entry["command"] as? String, command, client.displayName)
            XCTAssertEqual(entry["args"] as? [String], ["mcp"], client.displayName)
        }

        let code = ConfigClient.vsCode
        XCTAssertEqual(code.rootKey, "servers")
        XCTAssertEqual(code.entry(cli: cli)["type"] as? String, "stdio")
        XCTAssertEqual(code.entry(cli: cli)["command"] as? String, command)

        let openCode = ConfigClient.openCode
        XCTAssertEqual(openCode.rootKey, "mcp")
        XCTAssertEqual(openCode.entry(cli: cli)["type"] as? String, "local")
        XCTAssertEqual(openCode.entry(cli: cli)["command"] as? [String], [command, "mcp"])
        XCTAssertEqual(openCode.entry(cli: cli)["enabled"] as? Bool, true)
    }

    func testMergeKeepsOtherServersAndKeys() throws {
        let existing: [String: Any] = [
            "theme": "dark",
            "mcpServers": [
                "other": ["command": "/usr/bin/other"],
            ],
        ]
        let merged = ConfigClient.merged(existing, client: .cursor, cli: cli)
        XCTAssertEqual(merged["theme"] as? String, "dark")
        let servers = try XCTUnwrap(merged["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["other"], "别人的服务不能被删掉")
        XCTAssertEqual((servers["causality"] as? [String: Any])?["command"] as? String, cli.path)
    }

    func testMergeOnEmptyConfigProducesMinimalShape() throws {
        let merged = ConfigClient.merged([:], client: .claudeDesktop, cli: cli)
        let servers = try XCTUnwrap(merged["mcpServers"] as? [String: Any])
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual((servers["causality"] as? [String: Any])?["args"] as? [String], ["mcp"])
    }

    func testStaleEntryIsOverwrittenNotDuplicated() throws {
        let existing: [String: Any] = [
            "mcpServers": ["causality": ["command": "/old/path/causal", "args": ["mcp"]]],
        ]
        let merged = ConfigClient.merged(existing, client: .cursor, cli: cli)
        let servers = try XCTUnwrap(merged["mcpServers"] as? [String: Any])
        XCTAssertEqual(servers.count, 1, "不能留下两条同名")
        XCTAssertEqual((servers["causality"] as? [String: Any])?["command"] as? String, cli.path)
    }

    func testMergeIsIdempotent() throws {
        let once = ConfigClient.merged([:], client: .vsCode, cli: cli)
        let twice = ConfigClient.merged(once, client: .vsCode, cli: cli)
        let a = try JSONSerialization.data(withJSONObject: once, options: [.sortedKeys])
        let b = try JSONSerialization.data(withJSONObject: twice, options: [.sortedKeys])
        XCTAssertEqual(a, b, "重复写入不能改变内容")
    }
}

/// 在临时主目录里跑真实的写入与回读：备份、幂等、坏 JSON 不动手。
final class ConfigClientWriteTests: XCTestCase {
    private var home: URL!
    private let cli = URL(fileURLWithPath: "/Users/someone/.local/bin/causal")

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    private func write(_ contents: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    func testCreatesConfigWhenMissingThenVerifies() throws {
        let client = ConfigClient.cursor
        XCTAssertEqual(client.status(cli: cli, home: home), .notConfigured)

        let backup = try client.write(cli: cli, home: home)
        XCTAssertNil(backup, "原来没有文件，不该产生备份")
        XCTAssertEqual(client.status(cli: cli, home: home), .configured)

        let data = try Data(contentsOf: client.configURL(home: home))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(json["mcpServers"] as? [String: Any])
        XCTAssertEqual((servers["causality"] as? [String: Any])?["command"] as? String, cli.path)
    }

    func testKeepsExistingContentAndMakesBackup() throws {
        let client = ConfigClient.claudeDesktop
        let url = client.configURL(home: home)
        try write(#"{"theme":"dark","mcpServers":{"other":{"command":"/usr/bin/other"}}}"#, at: url)

        let backup = try XCTUnwrap(try client.write(cli: cli, home: home))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(backup.lastPathComponent.contains(".bak-mcp-"))

        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["theme"] as? String, "dark")
        let servers = try XCTUnwrap(json["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["other"])
        XCTAssertEqual(client.status(cli: cli, home: home), .configured)
    }

    func testSecondWriteIsIdempotentAndStalePathIsReplaced() throws {
        let client = ConfigClient.kiro
        try client.write(cli: cli, home: home)
        let first = try Data(contentsOf: client.configURL(home: home))
        try client.write(cli: cli, home: home)
        let second = try Data(contentsOf: client.configURL(home: home))
        XCTAssertEqual(first, second, "重复写入内容不变")

        // 指向旧位置时应报 stale，写完变 configured
        let other = URL(fileURLWithPath: "/old/place/causal")
        try client.write(cli: other, home: home)
        guard case .stalePath = client.status(cli: cli, home: home) else {
            return XCTFail("旧路径应判为 stalePath")
        }
        try client.write(cli: cli, home: home)
        XCTAssertEqual(client.status(cli: cli, home: home), .configured)
    }

    func testBadJSONIsLeftUntouched() throws {
        let client = ConfigClient.vsCode
        let url = client.configURL(home: home)
        let broken = "{ not json ,, "
        try write(broken, at: url)

        XCTAssertThrowsError(try client.write(cli: cli, home: home))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), broken, "解析不了就不许覆盖")
        if case .notWritable = client.status(cli: cli, home: home) {} else {
            XCTFail("坏 JSON 应显示为不可写")
        }
    }
}

/// 只存在一个空的 mcpServers 骨架文件，不代表装过这个客户端。
final class ConfigClientDetectionTests: XCTestCase {
    func testEmptyConfigSkeletonAloneIsNotInstalled() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-detect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        for client in [ConfigClient.kiro, .claudeDesktop, .cursor, .windsurf, .vsCode, .openCode] {
            let url = client.configURL(home: home)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(#"{"mcpServers": {}}"#.utf8).write(to: url)
            XCTAssertFalse(
                client.isInstalled(home: home),
                "\(client.displayName)：只有空配置文件不算安装"
            )
        }
    }
}
