import Foundation
import Testing
@testable import CausalityCore

@Suite("作品语言识别")
struct ProjectLanguageTests {
    private func project(_ title: String, _ body: String) -> StoryProject {
        var project = StoryProject.empty(title: title)
        project.nodes = [StoryNode(title: title, body: body, isEntry: true)]
        return project
    }

    @Test("英文正文识别为 en")
    func english() {
        let sample = project(
            "The Lantern",
            "Rain stops over the flooded square. The keeper's widow opens the door and sets the brass key on the table."
        )
        #expect(ProjectLanguage.detect(in: sample) == .english)
    }

    @Test("日文正文识别为 ja")
    func japanese() {
        let sample = project(
            "灯",
            "雨が止み、広場の水が引いていく。番人の未亡人が扉を開け、真鍮の鍵を机の上に置いた。"
        )
        #expect(ProjectLanguage.detect(in: sample) == .japanese)
    }

    @Test("繁体正文识别为 zh-Hant")
    func traditionalChinese() {
        let sample = project(
            "河燈",
            "雨停了，他放下行囊，接過鑰匙。廣場上的積水慢慢退去，遠處傳來鐘聲。"
        )
        #expect(ProjectLanguage.detect(in: sample) == .traditionalChinese)
    }

    @Test("简体正文识别为 zh-Hans")
    func simplifiedChinese() {
        let sample = project(
            "河灯",
            "雨停了，他放下行囊，接过钥匙。广场上的积水慢慢退去，远处传来钟声。"
        )
        #expect(ProjectLanguage.detect(in: sample) == .simplifiedChinese)
    }

    @Test("没有正文时判断不出")
    func empty() {
        #expect(ProjectLanguage.detect(in: StoryProject.empty(title: "")) == nil)
    }
}
