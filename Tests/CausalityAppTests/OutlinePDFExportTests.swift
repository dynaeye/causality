import AppKit
import PDFKit
import CausalityCore
import Testing
@testable import Causality

/// 打印用 PDF 的版式契约：A4、双栏、内容不丢、配图说明跟着配图。
@Suite("大纲 PDF 版式")
@MainActor
struct OutlinePDFExportTests {
    private static let a4Width: CGFloat = 595.28
    private static let a4Height: CGFloat = 841.89

    private static func makeProject(scenes: Int, withImage: Bool = false) throws -> (StoryProject, [AssetID: Data]) {
        var imageData: [AssetID: Data] = [:]
        var project = StoryProject.empty(title: "版式")
        try ProjectEditing.apply(ProjectMutations.updateHeader(title: "版式", logline: "一句话梗概。", in: project), to: &project)

        let chapter = Chapter(title: "第一幕")
        try ProjectEditing.apply(ProjectMutations.appendChapter(chapter, to: project), to: &project)

        for index in 1...scenes {
            var node = StoryNode(title: "场景\(index)", summary: "摘要\(index)", body: "第 \(index) 场的正文。")
            node.chapterID = chapter.id
            try ProjectEditing.apply(ProjectMutations.appendNode(node, to: project), to: &project)
        }

        if withImage, let nodeID = project.nodes.first?.id {
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )
            let png = bitmap?.representation(using: .png, properties: [:]) ?? Data()
            let asset = Asset(fileName: "cover.png", pixelWidth: 40, pixelHeight: 20, caption: "配图说明")
            try ProjectEditing.apply(ProjectMutations.updateNode(nodeID, in: project) { node in
                node.coverAssetID = asset.id
            }, to: &project)
            project.assets.append(asset)
            imageData[asset.id] = png
        }
        return (project, imageData)
    }

    @Test("六十场排出 A4 多页，标题一条不少")
    func paginatesWithoutLosingText() throws {
        let (project, _) = try Self.makeProject(scenes: 60)
        let data = try #require(OutlinePDFExport.makePDF(project: project, route: nil))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 2)

        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            let box = page.bounds(for: .mediaBox)
            #expect(abs(box.width - Self.a4Width) < 0.5)
            #expect(abs(box.height - Self.a4Height) < 0.5)
        }

        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        for index in 1...60 {
            #expect(text.contains("场景\(index)"), "第 \(index) 场在 PDF 里找不到")
        }
    }

    @Test("配图与说明进 PDF")
    func drawsImageAndCaption() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("causal-pdf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let (project, imageData) = try Self.makeProject(scenes: 2, withImage: true)
        let package = base.appendingPathComponent("工程.\(ProjectPackage.fileExtension)", isDirectory: true)
        _ = try ProjectPackage.save(project, to: package, newAssetData: imageData)

        let data = try #require(OutlinePDFExport.makePDF(project: project, route: nil, packageURL: package))
        let document = try #require(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        #expect(text.contains("配图说明"))
    }
}
