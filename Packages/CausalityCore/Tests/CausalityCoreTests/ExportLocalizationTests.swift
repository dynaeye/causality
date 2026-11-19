import Foundation
import Testing
@testable import CausalityCore

@Suite("导出标签跟作品语言")
struct ExportLocalizationTests {
    @Test("分支梗概的结构标签用传入语言")
    func branchSynopsisLocalizes() throws {
        let script = ConvergenceDemo.make(localize: CoreText.localizer(for: "en"))
        let ending = script.project.nodes.first { $0.kind == .ending }
        let endingID = try #require(ending?.id)
        let synopsis = BranchSynopsis.make(
            project: script.project,
            endingID: endingID,
            mode: .segments,
            localize: CoreText.localizer(for: "en")
        )
        let labels = Set(synopsis.blocks.map(\.label))
        #expect(labels.contains("Start"))
        #expect(labels.contains("Ending") || labels.contains("Merge"))
        #expect(!labels.contains("开始"))
        #expect(!labels.contains("汇合"))
    }

    @Test("试读稿标题与统计用传入语言")
    func playthroughLocalizes() throws {
        let script = ConvergenceDemo.make(localize: CoreText.localizer(for: "en"))
        let play = try #require(PlaythroughEngine.start(in: script.project))
        let markdown = PlaythroughMarkdown.render(
            play,
            project: script.project,
            localize: CoreText.localizer(for: "en")
        )
        #expect(markdown.hasPrefix("# 《\(script.project.title)》 Reading Copy"))
        #expect(markdown.contains("words total"))
        #expect(!markdown.contains("试读稿"))
    }
}
