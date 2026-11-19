import Foundation
import Testing
@testable import CausalityCore

/// 第三轮验收：点「从示例新建」拿到的工程跟随界面语言，中文原样不变。
///
/// `CoreText.localize` 是全局开关，两条用例必须串行跑，否则互相把语言切走。
@Suite("示例工程多语言", .serialized)
struct ConvergenceLocalizationTests {
    /// 汉字、汉字标点、假名、全角符号都算「中文残留」。
    private func hasCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000 ... 0x303F, 0x3040 ... 0x30FF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF, 0xFF00 ... 0xFF65:
                true
            default:
                false
            }
        }
    }

    private func hasKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040 ... 0x30FF).contains($0.value) }
    }

    /// 项目里所有面向读者的字符串。
    private func readerFacing(_ project: StoryProject) -> [String] {
        var strings = [project.title, project.logline]
        for chapter in project.chapters {
            strings += [chapter.title, chapter.summary]
        }
        for node in project.nodes {
            strings += [node.title, node.summary, node.body]
        }
        for edge in project.edges {
            strings += [edge.label, edge.condition, edge.annotation]
        }
        for character in project.characters {
            strings += [character.name, character.summary, character.notes]
        }
        for place in project.places {
            strings += [place.name, place.summary, place.notes]
        }
        for setting in project.settings {
            strings += [setting.title, setting.text]
        }
        return strings.filter { !$0.isEmpty }
    }

    private func labels(_ script: ConvergenceDemo.Script) -> [String] {
        [script.keepSecretLabel, script.askTownsfolkLabel, script.causeLabel]
    }

    @Test("示例工程随界面语言切换")
    func followsInterfaceLanguage() {
        let zh = ConvergenceDemo.make(localize: CoreText.localizer(for: "zh-Hans"))
        let en = ConvergenceDemo.make(localize: CoreText.localizer(for: "en"))
        let ja = ConvergenceDemo.make(localize: CoreText.localizer(for: "ja"))

        // en：任何字段都没有中日文
        let leaked = (readerFacing(en.project) + labels(en)).filter(hasCJK)
        #expect(leaked.isEmpty, "英文示例里还有中文：\(leaked)")

        // ja：含假名，标题与中文版不同
        #expect(readerFacing(ja.project).contains(where: hasKana))
        #expect(ja.project.title != zh.project.title)

        // zh：与改造前逐字一致
        #expect(zh.project.title == "河灯里的字")
        #expect(zh.project.logline == "一盏逆水漂来的河灯，灯底是母亲的字。")
        #expect(zh.project.chapters.map(\.title) == ["第一章", "第二章"])
        #expect(zh.project.characters.map(\.name) == ["阿禾", "梁婆婆"])
        #expect(zh.project.places.map(\.name) == ["旧渡口"])
        let lantern = zh.project.node(zh.lantern)
        #expect(lantern?.title == "阿禾捞起河灯")
        #expect(lantern?.body.hasPrefix("夜河上漂来一盏河灯。") == true)
        #expect(zh.keepSecretLabel == "阿禾答应替寄信人守密")
        #expect(zh.askTownsfolkLabel == "阿禾拿河灯去问镇民")
        #expect(zh.causeLabel == "旧渡口只有梁婆婆替人捎过家书")
    }

    @Test("Script 里的连线文字与工程里的连线一致")
    func scriptLabelsMatchEdges() {
        for language in ["zh-Hans", "en", "ja", "zh-Hant"] {
            let script = ConvergenceDemo.make(localize: CoreText.localizer(for: language))
            let edgeLabels = Set(script.project.edges.map(\.label))
            #expect(edgeLabels.contains(script.keepSecretLabel), "\(language) 少了守密那条连线文字")
            #expect(edgeLabels.contains(script.askTownsfolkLabel), "\(language) 少了问镇民那条连线文字")
            #expect(edgeLabels.contains(script.causeLabel), "\(language) 少了因果那条连线文字")
        }
    }
}
