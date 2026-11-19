import AppKit
import CausalityCore
import UniformTypeIdentifiers

extension ProjectSession {
    /// 文件菜单：把 Markdown 读成新项目。
    ///
    /// 有「节点与时机」表走故事板导入；普通 `# 标题 / ## 章 / ### 场 / 段落`
    /// 走散文导入。转出来的项目还没落盘，和「新建项目」一样等作者自己按 ⌘S 挑位置。
    func importStoryboard() {
        Task {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.message = InterfaceLanguage.label("选一个 Markdown（故事板表格，或普通 # 章 / ## 场 / 段落）")
            panel.prompt = InterfaceLanguage.label("导入")
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            guard let url = await FilePanels.url(panel) else { return }

            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let title = url.deletingPathExtension().lastPathComponent
                    .components(separatedBy: "_")
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                let result = try MarkdownImport.makeProject(fromMarkdown: text, title: title)
                guard await saveBeforeSwitching() else { return }
                open(project: result.project, at: nil)
                if !result.notes.isEmpty {
                    warnings.insert(contentsOf: result.notes, at: 0)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
