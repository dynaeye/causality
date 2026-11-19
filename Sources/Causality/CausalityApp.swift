import Foundation
import CausalityCore
import SwiftUI

@main
struct CausalityApp: App {
    @AppStorage(InterfaceLanguage.storageKey) private var language = InterfaceLanguage.system
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        CoreText.localize = { InterfaceLanguage.label($0) }
        // 菜单栏与「关于」由 bundle 的本地化决定，只在启动时解析一次；
        // 把选择写进进程自己的 AppleLanguages，下次启动 AppKit 那几块就跟着换。
        InterfaceLanguage.current.applyBundleLanguage()
        // 草稿只是过渡产物：超过 30 天没再动过就不必留着。
        // App 测试也会启动这个宿主，跑测试时不能动用户真实的草稿。
        if !Self.isRunningTests {
            DraftStore.purge()
            DraftStore.trim(keeping: 3)
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    var body: some Scene {
        // 单窗口：WindowGroup 会记住并恢复多个窗口，双击文件时容易开出一堆。
        Window(Text(verbatim: language.label("因果")), id: "main") {
            RootView()
                .environment(\.locale, language.locale)
        }
        .defaultSize(width: 1600, height: 980)
        .commands {
            AppCommands(language: language)
        }

        Settings {
            SettingsRootView()
                .environment(\.locale, language.locale)
        }
    }
}

struct SessionFocusedValueKey: FocusedValueKey {
    typealias Value = ProjectSession
}

extension FocusedValues {
    var projectSession: ProjectSession? {
        get { self[SessionFocusedValueKey.self] }
        set { self[SessionFocusedValueKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    let language: InterfaceLanguage
    @FocusedValue(\.projectSession) private var session
    @AppStorage("causal.showInspector") private var showInspector = true
    @AppStorage("causal.focusMode") private var focusMode = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(language.label("新建项目")) { session?.requestNewProject(useSample: false) }
                .keyboardShortcut("n", modifiers: .command)
            #if DEBUG
            // 开发用：河灯样本走 --sample 启动参数或这里，产品界面上不出现。
            Button(language.label("从示例新建")) { session?.requestNewProject(useSample: true) }
            #endif
            Divider()
            Button(language.label("打开项目…")) { session?.openWithPanel() }
                .keyboardShortcut("o", modifiers: .command)
            Button(language.label("重命名项目…")) { session?.beginRenameProject() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(session?.isOpen != true)
            Button(language.label("导入 Markdown…")) { session?.importStoryboard() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button(language.label("关闭项目")) { session?.requestClose() }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(session?.isOpen != true)
        }

        CommandGroup(replacing: .saveItem) {
            Button(language.label("保存")) { session?.requestSave() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(session == nil)
            Button(language.label("另存为…")) { session?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(session == nil)
            Divider()
            Button(language.label("导出 Markdown…")) { session?.exportMarkdown() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button(language.label("导出故事图 PNG…")) { session?.exportCanvasImage() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button(language.label("导出大纲 PDF…")) { session?.exportOutlinePDF() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(session == nil)
        }

        CommandGroup(replacing: .undoRedo) {
            Button(language.label("撤销")) { session?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(session?.canUndo != true)
            Button(language.label("重做")) { session?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(session?.canRedo != true)
        }

        CommandMenu(language.label("故事")) {
            Button(language.label("新建场景")) { session?.addNode() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(session == nil)
            Button(language.label("新建章节")) { session?.addChapter() }
                .disabled(session == nil)
            Button(language.label("新建灵感卡")) { session?.addIdeaCard() }
                .disabled(session == nil)
            Divider()
            Button(language.label("写作模式")) { session?.toggleWritingMode() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(session?.isOpen != true)
            Button(language.label("上一场")) { session?.stepWriting(-1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(session?.isWriting != true)
            Button(language.label("下一场")) { session?.stepWriting(1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(session?.isWriting != true)
            Button(language.label("新建下一场")) { session?.newNextWritingScene() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(session?.isWriting != true)
            Button(language.label("从本场分叉")) { session?.forkWritingScene() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(session?.isWriting != true)
            Button(language.label("体检")) { session?.showAudit() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(session?.isOpen != true)
            Button(language.label("分支梗概")) { session?.openSynopsis() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(session?.isOpen != true)
            Button(language.label("线索")) { session?.openThreads() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(session?.isOpen != true)
            Button(language.label("试玩")) { session?.startPlaythrough() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(session?.isOpen != true)
            Divider()
            Button(language.label("重排故事图")) { session?.arrangeCanvas() }
                .disabled(session == nil)
            Toggle(language.label("显示右栏"), isOn: $showInspector)
                .keyboardShortcut("i", modifiers: [.command, .option])
            Toggle(language.label("专注模式"), isOn: $focusMode)
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Picker("视图", selection: Binding(
                get: { session?.viewMode ?? .outline },
                set: { session?.viewMode = $0 }
            )) {
                ForEach(WorkbenchViewMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.displayName)).tag(mode)
                }
            }
        }

        // 「工具」：不用开终端就能把命令行装好，并拿到任何 AI 客户端都能用的 MCP 配置。
        CommandMenu(language.label("工具")) {
            Button(language.label("安装命令行工具")) { CLIToolActions.installCLI() }
            Button(language.label("复制 MCP 配置")) { CLIToolActions.copyMCPConfig() }
        }
    }
}
