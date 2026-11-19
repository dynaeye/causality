import Foundation

/// 一次 Markdown 导出做了什么。配图缺失时照实说，别让读者以为图还在。
public struct MarkdownExportReport: Sendable, Equatable {
    public var markdownURL: URL
    public var assetsDirectory: URL
    public var copiedAssetFileNames: [String]
    public var missingAssetFileNames: [String]
}

/// 大纲导出：Markdown 与它引用的配图放在一起，工程包移走后打开还能看到图。
public enum MarkdownExport {
    /// 写出 Markdown，并把正文引用到的配图复制到同级的 `assets/`。
    @discardableResult
    public static func write(
        project: StoryProject,
        route: StoryRoute? = nil,
        packageURL: URL? = nil,
        to markdownURL: URL,
        label: (String) -> String = { $0 }
    ) throws -> MarkdownExportReport {
        let document = route.map { OutlineMarkdown.document(project: project, route: $0, label: label) }
            ?? OutlineMarkdown.document(project: project, label: label)
        try document.markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        let assetsURL = markdownURL
            .deletingLastPathComponent()
            .appendingPathComponent(ProjectPackage.assetsDirectoryName, isDirectory: true)
        var copied: [String] = []
        var missing: [String] = []
        for fileName in document.assetFileNames {
            guard let packageURL else {
                missing.append(fileName)
                continue
            }
            let source = ProjectPackage.assetsDirectory(in: packageURL)
                .appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: source.path) else {
                missing.append(fileName)
                continue
            }
            let destination = assetsURL.appendingPathComponent(fileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: destination.path) {
                copied.append(fileName)
            } else if copy(source, to: destination) {
                copied.append(fileName)
            } else {
                missing.append(fileName)
            }
        }
        return MarkdownExportReport(
            markdownURL: markdownURL,
            assetsDirectory: assetsURL,
            copiedAssetFileNames: copied,
            missingAssetFileNames: missing
        )
    }

    private static func copy(_ source: URL, to destination: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }
}
