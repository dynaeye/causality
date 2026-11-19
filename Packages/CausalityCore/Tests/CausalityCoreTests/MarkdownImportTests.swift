import Foundation
import Testing
@testable import CausalityCore

@Suite("普通 Markdown 导入")
struct MarkdownImportTests {
    private static let prose = """
    # 雨夜来信

    **一个关于雨夜来信的故事。**

    ## 第一幕 · 来信

    ### 第一场 信封

    林远在雨夜收到一封信。信里约他今晚去钟楼。

    ### 第二场 赴约

    他撑着伞走到钟楼。守钟人抬头看了他一眼。

    ## 第二幕 · 重逢

    ### 第三场 钟楼

    守钟人认出姐姐的笔迹，打开了档案室。

    ## 人物

    | 名字 | 简介 |
    |---|---|
    | 林远 | 收信人。 |
    | 姐姐 | 写信人。 |
    """

    @Test("## 分章、### 分场、段落进正文")
    func proseChaptersAndScenes() throws {
        let result = try MarkdownImport.makeProject(fromMarkdown: Self.prose, title: "雨夜来信")
        #expect(result.mode == .prose)
        let project = result.project
        #expect(project.title == "雨夜来信")
        #expect(project.logline == "一个关于雨夜来信的故事。")
        #expect(project.chapters.map(\.title) == ["第一幕 · 来信", "第二幕 · 重逢"])
        let scenes = project.nodes.filter { $0.status == .draft }
        #expect(scenes.map(\.title) == ["第一场 信封", "第二场 赴约", "第三场 钟楼"])
        #expect(scenes[0].body.contains("林远在雨夜收到一封信"))
        #expect(scenes[0].summary.hasPrefix("林远在雨夜收到一封信"))
        #expect(project.edges.count == 2)
        #expect(scenes[0].isEntry)
        #expect(result.notes.first?.contains("2 章 3 场") == true)
    }

    @Test("文内人物表按名字挂到场景，不预置示例库")
    func libraryFromProse() throws {
        let project = try MarkdownImport.makeProject(fromMarkdown: Self.prose).project
        let scenes = project.nodes.filter { $0.status == .draft }
        let lin = try #require(project.characters.first { $0.name == "林远" })
        let sister = try #require(project.characters.first { $0.name == "姐姐" })
        #expect(project.characters.count == 2)
        #expect(!project.characters.contains { $0.name == "姨母" })
        #expect(scenes[0].characterIDs.contains(lin.id))
        #expect(scenes[2].characterIDs.contains(sister.id))
    }

    @Test("没有 ### 时一章并成一场")
    func flatChapters() throws {
        let text = """
        # 平铺

        ## 第一章

        第一段。

        ## 第二章

        第二段。
        """
        let project = try MarkdownImport.makeProject(fromMarkdown: text).project
        #expect(project.chapters.map(\.title) == ["第一章", "第二章"])
        let scenes = project.nodes.filter { $0.status == .draft }
        #expect(scenes.count == 2)
        #expect(project.edges.count == 1)
    }

    @Test("自动识别：有节点表走故事板，普通文本走散文")
    func autoDetection() throws {
        let board = """
        # 表

        ## 第一幕

        | 节点与时机 | 眼前 | 动手 | 留下 |
        |---|---|---|---|
        | S01 入镇 | 下雨。 | 放行李。 | 拿到钥匙。 |
        """
        let boardResult = try MarkdownImport.makeProject(fromMarkdown: board)
        #expect(boardResult.mode == .storyboard)
        #expect(boardResult.project.nodes.count == 1)

        let prose = try MarkdownImport.makeProject(fromMarkdown: "# 散\n\n两个字。")
        #expect(prose.mode == .prose)
        #expect(prose.project.nodes.count == 1)
    }
}
