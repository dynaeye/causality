import Foundation
import CausalityCore
import Testing
@testable import Causality

@Suite("Interface language resources")
struct InterfaceLanguageTests {
    @Test func packagedLanguages() {
        #expect(InterfaceLanguage.simplified.label("新建项目") == "新建项目")
        #expect(InterfaceLanguage.traditional.label("新建项目") == "新建專案")
        #expect(InterfaceLanguage.english.label("新建项目") == "New Project")
        #expect(InterfaceLanguage.japanese.label("新建项目") == "新規プロジェクト")
        #expect(InterfaceLanguage.system.identifier == Bundle.main.preferredLocalizations.first)
    }

    @Test func allKeysHaveTranslations() throws {
        func keys(_ language: InterfaceLanguage) throws -> Set<String> {
            let url = try #require(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: language.rawValue + ".lproj"))
            let data = try Data(contentsOf: url)
            let entries = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            #expect(entries.values.allSatisfy { !$0.isEmpty })
            return Set(entries.keys)
        }
        let source = try keys(.simplified)
        for language in [InterfaceLanguage.english, .japanese, .traditional] {
            #expect(try keys(language) == source)
        }
    }
}

@Suite("Language-dependent copy", .serialized)
struct SaveStateLanguageTests {
    @Test func saveStateFollowsSelectedLanguage() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: InterfaceLanguage.storageKey)
        defer {
            if let saved {
                defaults.set(saved, forKey: InterfaceLanguage.storageKey)
            } else {
                defaults.removeObject(forKey: InterfaceLanguage.storageKey)
            }
        }

        defaults.set(InterfaceLanguage.english.rawValue, forKey: InterfaceLanguage.storageKey)
        #expect(SaveState.dirty.displayText == "Unsaved")
        #expect(SaveState.saving.displayText == "Saving…")
        #expect(SaveState.saved(.now).displayText == "Saved")

        let findings = NarrativeAudit.run(project: StoryProject.empty(title: "Probe"))
        #expect(findings.contains { $0.title == "No Explicit Entry" })
        #expect(findings.allSatisfy { !$0.title.contains("没有") })
    }

    @Test @MainActor func workLanguagePrefersContentOverInterface() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: InterfaceLanguage.storageKey)
        defer {
            if let saved {
                defaults.set(saved, forKey: InterfaceLanguage.storageKey)
            } else {
                defaults.removeObject(forKey: InterfaceLanguage.storageKey)
            }
        }

        defaults.set(InterfaceLanguage.english.rawValue, forKey: InterfaceLanguage.storageKey)
        let session = ProjectSession()
        var project = StoryProject.empty(title: "河灯")
        project.nodes = [
            StoryNode(
                title: "捞灯",
                body: "雨停了，他放下行囊，接过钥匙。广场上的积水慢慢退去，远处传来钟声。",
                isEntry: true
            )
        ]
        session.open(project: project, at: nil)
        #expect(session.workLanguage == .simplified)
    }
}

@Suite("Start page subtitle")
struct StartPageSubtitleTests {
    @Test func englishShowsTraditionalSubtitle() {
        #expect(InterfaceLanguage.english.label("每个故事都有起因，每个选择都有回响。") == "每個故事都有起因，每個選擇都有回響。")
    }
}
