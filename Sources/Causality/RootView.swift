import AppKit
import CausalityCore
import SwiftUI

struct RootView: View {
    @State private var session = ProjectSession()
    @State private var showingErrorHistory = false
    @AppStorage(InterfaceLanguage.storageKey) private var interfaceLanguage = InterfaceLanguage.system
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(ColorPreset.storageKey) private var presetRaw = ColorPreset.catppuccin.rawValue
    @Environment(\.colorScheme) private var systemColorScheme

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    private var theme: Theme {
        Theme.resolve(
            appearance,
            system: systemColorScheme,
            preset: ColorPreset(rawValue: presetRaw) ?? .catppuccin
        )
    }

    var body: some View {
        Group {
            if session.isOpen {
                WorkbenchView(session: session)
                    .focusedSceneValue(\.projectSession, session)
            } else {
                StartView(session: session)
            }
        }
        .navigationTitle(Text(verbatim: interfaceLanguage.label("因果")))
        .frame(minWidth: 980, minHeight: 640)
        .background(theme.background)
        .environment(\.theme, theme)
        .focusedSceneValue(\.projectSession, session)
        .background(TitlebarSeparator())
        .onAppear {
            AppearanceController.apply(appearance)
            openPendingProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProject)) { note in
            guard let url = note.object as? URL else { return }
            session.openProjectFromFinder(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            // 关窗后进程会结束，把还卡在防抖里的最后一笔改动先写下去。
            // 设置窗口、面板关闭也会发这个通知，只认主窗口。
            guard let window = note.object as? NSWindow,
                  !(window is NSPanel),
                  window === NSApp.mainWindow || window.identifier?.rawValue == "main"
            else { return }
            session.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            // 切到别的 App 前把正文草稿落一笔，崩溃或断电不丢最后一段。
            session.commitAllTextDrafts()
        }
        .onChange(of: appearanceRaw) { _, _ in AppearanceController.apply(appearance) }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            let launchMode: WorkbenchViewMode? = arguments.contains("--storyboard") ? .storyboard
                : arguments.contains("--outline") ? .outline
                : arguments.contains("--mindmap") ? .mindmap
                : arguments.contains("--canvas") ? .canvas
                : nil
            if arguments.contains("--new-project"), !session.isOpen {
                session.newProject(useSample: false)
                return
            }
            if let index = arguments.firstIndex(of: "--open"), index + 1 < arguments.count, !session.isOpen {
                session.openExisting(at: URL(fileURLWithPath: arguments[index + 1]))
                if let launchMode { session.viewMode = launchMode }
                if let chapter = arguments.firstIndex(of: "--chapter"), chapter + 1 < arguments.count {
                    // 开发用：把故事板横向滚到某一章，方便核对章节列。
                    session.focusedChapterID = session.project?.chapters
                        .first { $0.title == arguments[chapter + 1] }?.id
                }
                if let select = arguments.firstIndex(of: "--select"), select + 1 < arguments.count {
                    // 开发用：按标题选中一张卡，方便截界面。
                    let title = arguments[select + 1]
                    session.selectedNodeID = session.project?.nodes.first { $0.title == title }?.id
                }
                if let pdf = arguments.firstIndex(of: "--export-pdf"), pdf + 1 < arguments.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        session.debugExportPDF(to: arguments[pdf + 1])
                    }
                }
                if let png = arguments.firstIndex(of: "--export-png"), png + 1 < arguments.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        session.debugExportCanvas(to: arguments[png + 1])
                    }
                }
                if let search = arguments.firstIndex(of: "--search"), search + 1 < arguments.count {
                    // 开发用：带一段搜索词进界面。
                    session.searchText = arguments[search + 1]
                }
                if let character = arguments.firstIndex(of: "--character"), character + 1 < arguments.count {
                    // 开发用：按名字选中一个���物，方便截人物脉络的界面。
                    let name = arguments[character + 1]
                    session.focusedCharacterID = session.project?.characters.first { $0.name == name }?.id
                }
                if let route = arguments.firstIndex(of: "--route"), route + 1 < arguments.count {
                    // 开发用：直接只看通往某个结局的路径。
                    let title = arguments[route + 1]
                    session.routeEndingID = session.project?.nodes.first { $0.title == title }?.id
                }
                if arguments.contains("--ai") { session.detailMode = .ai }
                if arguments.contains("--ai-settings") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { session.openAISettings() }
                }
                return
            }
            if arguments.contains("--sample"), !session.isOpen {
                session.newProject(useSample: true)
                if let launchMode {
                    session.viewMode = launchMode
                }
                if arguments.contains("--ai") {
                    session.detailMode = .ai
                }
                if arguments.contains("--ai-settings") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { session.openAISettings() }
                }
            }
        }
        .alert(
            "出错了",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )
        ) {
            if case .failed = session.saveState {
                Button("重试保存") { session.retrySave() }
            }
            if session.errorHistory.count > 1 {
                Button("最近错误…") {
                    session.errorMessage = nil
                    showingErrorHistory = true
                }
            }
            Button("好") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
        .sheet(isPresented: $showingErrorHistory) {
            ErrorHistoryView(session: session)
        }
    }

    /// 冷启动时从系统接住的双击文件。
    @MainActor
    private func openPendingProject() {
        guard let url = AppDelegate.takePendingURL() else { return }
        session.openProjectFromFinder(url)
    }
}

// MARK: - 起始页

struct StartView: View {
    @Bindable var session: ProjectSession
    @State private var drafts: [URL] = []
    @State private var draftPendingDelete: URL?
    /// 与品牌区的英文副标题同宽，最近打开/草稿列表的左边线才对得上。
    private let contentWidth: CGFloat = 363

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image("BrandMark")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 112, height: 112)
                        .padding(.bottom, 4)
                    BrandWordmark(size: 34)
                    VStack(spacing: 3) {
                        Text("Every Story Has a Cause. Every Choice Has a Consequence.")
                            .font(.system(size: 13, weight: .regular, design: .serif))
                            .foregroundStyle(.secondary)
                        Text("每个故事都有起因，每个选择都有回响。")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                }
                .frame(width: contentWidth)
                .padding(.bottom, 6)

                HStack(spacing: 12) {
                    Button("新建项目") { session.newProject(useSample: false) }
                        .buttonStyle(.borderedProminent)
                    Button("打开项目…") { session.openWithPanel() }
                }
                .padding(.top, 10)
            }

            if !drafts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("未保存的草稿")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(drafts, id: \.self) { url in
                        HStack(spacing: 4) {
                            Button {
                                session.openExisting(at: url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.badge.clock")
                                    Text(DraftStore.title(of: url))
                                        .lineLimit(1)
                                    Text("未保存")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                draftPendingDelete = url
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .help("删除这份草稿（移到废纸篓）")
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .contextMenu {
                            Button("移到废纸篓", role: .destructive) { draftPendingDelete = url }
                        }
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.top, 24)
            }

            if !session.recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近打开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(session.recentProjects.prefix(5), id: \.self) { url in
                        Button {
                            session.openExisting(at: url)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("在 Finder 中显示") { revealInFinder(url) }
                            Divider()
                            Button("另存为…") { duplicateProject(url) }
                            Button("复制路径") { copyPath(url) }
                        }
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.top, 36)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { drafts = DraftStore.trim(keeping: 3, except: session.packageURL) }
        .alert(
            "删除草稿？",
            isPresented: Binding(
                get: { draftPendingDelete != nil },
                set: { if !$0 { draftPendingDelete = nil } }
            ),
            presenting: draftPendingDelete
        ) { url in
            Button("移到废纸篓", role: .destructive) { discardDraft(url) }
            Button("取消", role: .cancel) { draftPendingDelete = nil }
        } message: { url in
            Text(String(format: InterfaceLanguage.label("「%@」还没有保存到正式位置。删除会把整个工程包移到废纸篓，之后可以从废纸篓恢复。"), DraftStore.title(of: url)))
        }
    }

    /// 草稿进废纸篓：删除不可怕，可怕的是一键后就找不回来。
    private func discardDraft(_ url: URL) {
        draftPendingDelete = nil
        guard DraftStore.discard(url) else {
            session.errorMessage = String(format: InterfaceLanguage.label("无法把草稿移到废纸篓：%@"), url.lastPathComponent)
            return
        }
        drafts = DraftStore.trim(keeping: 3, except: session.packageURL)
    }

    // MARK: 最近打开的右键菜单

    @MainActor
    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    private func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    /// 复制整个工程包。另存为的位置不能是原包，也不能塞进原包里面。
    @MainActor
    private func duplicateProject(_ url: URL) {
        Task { @MainActor in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(url.deletingPathExtension().lastPathComponent) \(InterfaceLanguage.label("副本")).\(ProjectPackage.fileExtension)"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            guard let destination = await FilePanels.url(panel) else { return }

            let source = url.standardizedFileURL
            let target = destination.standardizedFileURL
            guard target != source, !target.path.hasPrefix(source.path + "/") else {
                session.errorMessage = InterfaceLanguage.label("另存为的位置不能是原工程或它里面的目录。")
                return
            }
            do {
                let fileManager = FileManager.default
                let staged = target.deletingLastPathComponent()
                    .appendingPathComponent(
                        "\(target.lastPathComponent).\(UUID().uuidString.prefix(8)).incoming",
                        isDirectory: true
                    )
                do {
                    try? fileManager.removeItem(at: staged)
                    try fileManager.copyItem(at: source, to: staged)
                    try ProjectPackage.replacePackage(at: target, with: staged)
                } catch {
                    // 换失败：暂存的副本不要留在用户目录里。
                    try? fileManager.removeItem(at: staged)
                    throw error
                }
            } catch {
                session.errorMessage = String(format: InterfaceLanguage.label("另存为失败：%@"), error.localizedDescription)
            }
        }
    }

}

// MARK: - 工作区

struct WorkbenchView: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    @AppStorage("causal.showInspector") private var showInspector = true
    @AppStorage("causal.focusMode") private var focusMode = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var panelVisible: Bool {
        showInspector && !focusMode && !session.isWriting && !session.isAuditing && !session.isSynopsizing && !session.isThreading && !session.isPlaying
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarPane(session: session)
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                // 四个视图共用一条顶线，人物与故事图不再贴到工具栏上。
                PaneTopRule()
                Group {
                    if session.isAuditing {
                        AuditPane(session: session)
                    } else if session.isSynopsizing {
                        SynopsisPane(session: session)
                    } else if session.isThreading {
                        ThreadPane(session: session)
                    } else if session.isPlaying {
                        PlaythroughPane(session: session)
                    } else if session.isWriting {
                        WritingPane(session: session)
                    } else {
                        switch session.viewMode {
                        case .storyboard:
                            StoryboardPane(session: session, inspectorWidth: panelVisible ? 420 : 0)
                        case .outline:
                            OutlinePane(session: session, inspectorWidth: panelVisible ? 420 : 0)
                        case .mindmap:
                            MindMapPane(session: session, inspectorWidth: panelVisible ? 420 : 0)
                        case .canvas:
                            CanvasPane(session: session, inspectorWidth: panelVisible ? 420 : 0)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 520, ideal: 760)
            .toolbar { toolbarContent }
            // 右栏浮在内容之上：开合不改变内容区宽度，卡片/列表不会被挤着重排。
            .overlay(alignment: .trailing) {
                if panelVisible {
                    detailPanel
                        .frame(width: 420)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .alert("重命名项目", isPresented: $session.showingRename) {
            TextField("项目名", text: $session.renameDraft)
            Button("确定") { session.commitRenameProject() }
            Button("取消", role: .cancel) { session.showingRename = false }
        } message: {
            Text("保存时工程包的名字会跟着改。")
        }
        .alert("工程包已被其它程序改动", isPresented: $session.hasSaveConflict) {
            Button("另存为…") { session.resolveConflictBySavingAs() }
            Button("覆盖磁盘", role: .destructive) { session.resolveConflictByOverwriting() }
            Button("重新载入磁盘", role: .destructive) { session.resolveConflictByReloadingDisk() }
            Button("取消", role: .cancel) { session.dismissSaveConflict() }
        } message: {
            Text(session.conflictMessage ?? InterfaceLanguage.label("磁盘上的工程包已经变了。另存为可以保住两边的改动。"))
        }
        .navigationTitle(session.project?.title ?? InterfaceLanguage.label("因果"))
        .navigationSubtitle(session.saveState.displayText)
        .toolbar(removing: .title)
        .onAppear {
            columnVisibility = focusMode ? .detailOnly : .all
        }
        .onChange(of: focusMode) { _, isFocused in
            withAnimation(.easeInOut(duration: 0.18)) {
                columnVisibility = isFocused ? .detailOnly : .all
            }
        }

        .sheet(isPresented: $session.showingProposalSheet) {
            ProposalReviewSheet(session: session)
        }

    }

    /// 右栏：详情 / AI 辅助。浮在内容之上，不参与内容区排版。
    private var detailPanel: some View {
        VStack(spacing: 0) {
            Picker("右栏", selection: $session.detailMode) {
                ForEach(DetailMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.displayName)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
            Divider()
            switch session.detailMode {
            case .inspector:
                InspectorPane(session: session)
            case .ai:
                AIPanel(session: session)
            }
        }
        .background(theme.background)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.border)
                .frame(width: 1)
                .ignoresSafeArea()
        }
        .shadow(color: .black.opacity(0.10), radius: 8, x: -2, y: 0)
    }

    /// 顶栏中间的标题：纯文字，后面跟一个间隔点与保存状态。
    @ToolbarContentBuilder
    private var principalTitle: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // macOS 26 会给工具项套一层玻璃底，标题要纯文字就得关掉。
            ToolbarItem(placement: .principal) { titleText }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { titleText }
        }
        #else
        // Xcode 16 的 SDK 没有 sharedBackgroundVisibility，保持普通工具项。
        ToolbarItem(placement: .principal) { titleText }
        #endif
    }

    private var titleText: some View {
        HStack(spacing: 7) {
            if false {
                TextField("项目名", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(width: 200)
                    .focused($titleFocused)
                    .onSubmit(commitTitle)
                    .onExitCommand { editingTitle = false }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitTitle() }
                    }
                    .onAppear { titleFocused = true }
            } else {
                // 顶栏的工具项收不到点击，改名走「文件 → 重命名项目…」（⇧⌘R）。
                Text(session.project?.title ?? InterfaceLanguage.label("因果"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if !session.saveState.displayText.isEmpty {
                Text("|")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                Text(verbatim: session.saveState.displayText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    /// 提交项目名：走编辑操作，⌘Z 就能还原。
    private func commitTitle() {
        // 回车与失焦都会调到这里，用 editingTitle 做闸，只提交一次。
        guard editingTitle else { return }
        editingTitle = false
        guard let project = session.project else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        session.apply(
            ProjectMutations.updateHeader(title: trimmed, in: project),
            name: InterfaceLanguage.label("改项目名")
        )
    }

    /// 搜索自己一个圆角，不跟右边的按钮挤在同一个玻璃底里。
    @ToolbarContentBuilder
    private var searchToolbarItem: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { searchField }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { searchField }
        }
        #else
        ToolbarItem(placement: .primaryAction) { searchField }
        #endif
    }

    /// 顶栏右侧的搜索框：窄栏，空着时放大镜与提示语整体居中。
    private var searchField: some View {
        HStack(spacing: 6) {
            if !session.searchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            TextField("", text: $session.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .overlay {
                    if session.searchText.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                            Text("搜索人名、地点、事件")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 9)
        .frame(width: 260, height: 24)
        .background(
            Color.primary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("视图", selection: Binding(
                get: { session.viewMode },
                set: { mode in
                    session.viewMode = mode
                    session.isWriting = false
                    session.isAuditing = false
                    session.isSynopsizing = false
                    session.isThreading = false
                    session.isPlaying = false
                }
            )) {
                ForEach(WorkbenchViewMode.allCases) { mode in
                    Label(LocalizedStringKey(mode.displayName), systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
        principalTitle
        searchToolbarItem
        ToolbarItemGroup(placement: .primaryAction) {
            if session.auditErrorCount > 0 {
                Button {
                    session.showAudit()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(session.auditErrorCount)")
                    }
                    .foregroundStyle(.red)
                }
                .help(String(format: InterfaceLanguage.label("体检：%lld 个错误"), session.auditErrorCount))
            }

            Button {
                session.toggleWritingMode()
            } label: {
                Label("写作模式", systemImage: "square.and.pencil")
            }
            .help("写作模式（⌘⏎）")

            Button {
                if !panelVisible {
                    showInspector = true
                    focusMode = false
                    session.isWriting = false
                    session.isAuditing = false
                    session.isSynopsizing = false
                    session.isThreading = false
                    session.isPlaying = false
                    session.detailMode = .ai
                } else {
                    session.detailMode = session.detailMode == .ai ? .inspector : .ai
                }
            } label: {
                Label("AI 辅助", systemImage: session.detailMode == .ai ? "sparkles.rectangle.stack.fill" : "sparkles")
            }
            .help("在右栏打开 AI 辅助")

            Button {
                session.addNode()
            } label: {
                Label("新建场景", systemImage: "plus.rectangle")
            }
            .help("新建场景（⌥⌘N）")

            Button {
                session.exportMarkdown()
            } label: {
                Label("导出 Markdown", systemImage: "doc.plaintext")
            }
            .help("导出 Markdown（⇧⌘E）")

            Button {
                if panelVisible {
                    showInspector = false
                } else {
                    showInspector = true
                    focusMode = false
                    session.isWriting = false
                    session.isAuditing = false
                    session.isSynopsizing = false
                    session.isThreading = false
                    session.isPlaying = false
                }
            } label: {
                Label("右栏", systemImage: panelVisible ? "sidebar.right" : "sidebar.leading")
            }
            .help("显示或收起右栏（⌥⌘I）；专注模式 ⌥⌘R")

            Button {
                session.requestClose()
            } label: {
                Label("关闭项目", systemImage: "xmark.circle")
            }
            .help("关闭项目")
        }
    }
}

/// 批量操作时按时间倒序展示最近错误；单条错误仍然走 alert，不打断写作。
struct ErrorHistoryView: View {
    @Bindable var session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近错误")
                    .font(.headline)
                Spacer()
                Button("清空") { session.clearErrorHistory() }
                    .disabled(session.errorHistory.isEmpty)
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(session.errorHistory.reversed().enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minWidth: 420, minHeight: 240, maxHeight: 360)
        }
        .padding(20)
    }
}
