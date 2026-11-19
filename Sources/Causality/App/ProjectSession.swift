import AppKit
import Foundation
import Observation
import CausalityCore
import UniformTypeIdentifiers

enum DetailMode: String, CaseIterable, Identifiable {
    case inspector
    case ai

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .inspector: "详情"
        case .ai: "AI 辅助"
        }
    }
}

enum WorkbenchViewMode: String, CaseIterable, Identifiable {
    case storyboard
    case outline
    case mindmap
    case canvas

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .storyboard: "故事板"
        case .outline: "大纲"
        case .mindmap: "人物脉络"
        case .canvas: "故事图"
        }
    }
    var symbolName: String {
        switch self {
        case .storyboard: "rectangle.split.3x1"
        case .outline: "list.bullet.indent"
        case .mindmap: "person.2"
        case .canvas: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

enum SaveState: Equatable {
    case idle
    case dirty
    case saving
    case saved(Date)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle: ""
        case .dirty: InterfaceLanguage.label("未保存")
        case .saving: InterfaceLanguage.label("保存中…")
        case .saved: InterfaceLanguage.label("已保存")
        case let .failed(message): String(format: InterfaceLanguage.label("保存失败：%@"), message)
        }
    }
}

/// 一次保存的结局。换工程、关窗之前先看它：没落盘就不动当前窗口。
enum SaveOutcome: Equatable {
    case saved
    /// 用户取消，或这次写已经过期（期间又存了一次 / 换了工程）。
    case cancelled
    case failed(String)
    /// 磁盘被人改过，已经进入冲突流程。
    case conflict(String)

    var isSaved: Bool { self == .saved }
}

/// 一个窗口对应的一个项目。所有修改经过编辑器，保存与自动保存都在这里。
@MainActor
@Observable
final class ProjectSession {
    private(set) var editor: StoryEditor?
    private(set) var packageURL: URL?
    private(set) var pendingAssets: [AssetID: Data] = [:]
    var warnings: [String] = []
    /// 单条错误照旧走 alert；同时把最近几条留在 errorHistory，批量失败时不会被后一条盖掉。
    var errorMessage: String? {
        didSet {
            guard let message = errorMessage, !message.isEmpty, message != oldValue else { return }
            if errorHistory.last != message {
                errorHistory.append(message)
                if errorHistory.count > 20 { errorHistory.removeFirst(errorHistory.count - 20) }
            }
        }
    }
    private(set) var errorHistory: [String] = []
    var saveState: SaveState = .idle
    /// 打开 / 上次保存时的磁盘指纹。保存时带上它，磁盘被别的程序改过就报冲突。
    private(set) var lastStamp: PackageStamp?
    var hasSaveConflict = false
    private(set) var conflictMessage: String?
    /// 撤销栈的可用状态。编辑器的状态在 StoryEditor 里，菜单只观察会话，所以在这里镜像一份。
    private(set) var canUndo = false
    private(set) var canRedo = false

    private(set) var outlines: [ChapterOutline] = []
    private(set) var projectIndex: ProjectIndex?
    /// 写作模式的线性顺序，跟大纲的 DFS 分开算。
    private(set) var writingScenes: [WritingScene] = []
    /// 四级字数（场景 / 章 / 路线 / 全书）。每次刷新只算一遍，界面直接读。
    private(set) var wordCounts: WordCount.Book = .empty
    /// 长文本的编辑草稿。输入法组字期间只改这里，停输 400 ms 或失焦再进模型。
    var textDrafts: [TextDraftField: String] = [:]
    @ObservationIgnored var textDraftTasks: [TextDraftField: Task<Void, Never>] = [:]
    /// 主线：入口沿主线去向走到结局的那串节点与连线。
    private(set) var mainline: Mainline = .empty
    /// 体检结果（异步刷新，已按忽略表过滤）。
    var auditFindings: [AuditFinding] = []
    var auditWaivedFindings: [AuditFinding] = []
    @ObservationIgnored var auditTask: Task<Void, Never>?

    var viewMode: WorkbenchViewMode = .storyboard
    var detailMode: DetailMode = .inspector
    var selectedNodeID: NodeID? {
        didSet { rememberWritingScene() }
    }
    /// 写作模式：中栏只显示当前这一场，顺序走 `chapter.order`。
    var isWriting = false
    /// 体检面板：中栏显示问题清单。
    var isAuditing = false
    /// 分支梗概面板。
    var isSynopsizing = false
    /// 线索账本面板。
    var isThreading = false
    /// 试玩。
    var isPlaying = false
    var playthrough: Playthrough?
    var focusedThreadID: ThreadID?
    var synopsisMode: BranchSynopsis.Mode = .segments
    var synopsisGroups: [BranchSynopsis] = []
    var synopsisPolish: [String: String] = [:]
    var synopsisPolishErrors: [String: String] = [:]
    var synopsisPolishing: Set<String> = []
    /// 故事板上被折叠的并列组（按分叉点记，只在本次会话）。
    var collapsedAlternateGroups: Set<NodeID> = []
    var searchText: String = ""
    var focusedChapterID: ChapterID?
    /// 人物脉络里选中的那个人。右栏按它切换成人物编辑。
    var focusedCharacterID: CharacterID?
    /// 大纲里被折叠的章（只在本次会话里记，不进工程包）。
    var collapsedChapters: Set<ChapterID> = []
    /// 只看通往某个结局的路径；nil 表示看全部。
    var routeEndingID: NodeID?

    /// 工程里所有结局，供筛选菜单用。
    var endings: [StoryNode] {
        (project?.nodes ?? []).filter { $0.kind == .ending }
    }

    /// 当前筛选下的路径；没筛选就是 nil。
    var activeRoute: StoryRoute? {
        guard let routeEndingID, let project else { return nil }
        return StoryRoute.paths(to: routeEndingID, in: project)
    }

    /// 大纲按筛选走：只看某条路时，范围外的卡不进列表。
    var displayedOutlines: [ChapterOutline] {
        guard let route = activeRoute else { return outlines }
        return outlines
            .map { $0.filtered(to: route.nodeIDs) }
            .filter { !$0.rows.isEmpty }
    }

    // MARK: AI 状态

    /// AI 服务设置属于整个 App，放在系统设置窗口里。
    @ObservationIgnored let ai = AISettingsStore.shared

    var aiProvider: AIProvider { ai.provider(for: .planning) ?? ai.provider }
    var aiModel: String { ai.model(for: .planning) }
    var aiModelOptions: [String] { ai.availableModels(for: .planning) }
    var aiModelFetching: Bool { ai.fetching }
    var aiModelError: String? { ai.error }
    var aiModelNotice: String? { ai.notice }
    var aiHasCredential: Bool { ai.hasCredential }
    var aiCredentialSavedAt: Date? { ai.savedAt }
    var aiContextScope: AIContextScope = .selection
    var aiInstruction: String = ""
    var aiExcludedReferences: Set<String> = []
    var aiState: AIState = .idle
    var aiDiscussionID: DiscussionID?
    var aiLastContext: AIContext?
    var pendingProposal: ValidatedProposal?
    var showingProposalSheet = false
    var aiLastError: String?
    var aiSessionID: String { ai.sessionID }
    /// 故事板上作者点下的那一处缝隙。AI 的“这里”就是它。
    var insertion: CardInsertionPoint?

    @ObservationIgnored var aiTask: Task<Void, Never>?
    @ObservationIgnored let proposalService = ProposalService()
    @ObservationIgnored let aiClient = AIClient()

    @ObservationIgnored var autosaveTask: Task<Void, Never>?
    /// 保存本身串行：正在存的时候再按 ⌘S，等的是同一笔结果。
    @ObservationIgnored private var saveInFlight: Task<SaveOutcome, Never>?
    @ObservationIgnored private var saveFlightID: UUID?
    /// 当前工程的身份证。换工程时换一个，旧的写盘回调据此作废。
    @ObservationIgnored private var sessionToken = UUID()
    /// 模型内容的版本号：每改一次 +1。存完对一次，确认最后一笔已经落盘。
    @ObservationIgnored private(set) var editRevision = 0
    /// 最近一次成功写盘覆盖到的版本号。
    @ObservationIgnored private(set) var savedRevision = 0
    /// 后台落盘队列与代次：过期的写结果直接丢掉。
    @ObservationIgnored private let saveQueue: SaveQueue
    @ObservationIgnored private var saveGeneration = 0

    /// 写盘队列可以注入，故障演练与 App 层测试靠它暂停写盘。
    init(saveQueue: SaveQueue = SaveQueue()) {
        self.saveQueue = saveQueue
    }
    /// 当前打开的是没落过正式位置的草稿。
    var isDraft = false
    /// 重命名对话框。
    var showingRename = false
    var renameDraft = ""
    private static let recentsKey = "causal.recentProjects"
    // MARK: 打开与新建

    var project: StoryProject? { editor?.project }

    /// 作品内容语言。导出与 AI 提示词按它走；判断不出时回落到界面语言。
    var workLanguage: InterfaceLanguage {
        guard let project,
              let detected = ProjectLanguage.detect(in: project),
              let language = InterfaceLanguage(rawValue: detected.rawValue) else {
            return .current
        }
        return language
    }

    var isOpen: Bool { editor != nil }

    func newProject(useSample: Bool) {
        if useSample {
            open(project: ConvergenceDemo.make().project, at: nil)
            return
        }
        var project = StoryProject.empty(title: InterfaceLanguage.label("未命名项目"))
        let chapterID = ChapterID()
        let first = StoryNode(title: InterfaceLanguage.label("第一张卡"), chapterID: chapterID, isEntry: true)
        var withFirst = project
        do {
            try ProjectEditing.apply(
                ProjectMutations.appendChapter(Chapter(id: chapterID, title: InterfaceLanguage.label("第一章")), to: project),
                to: &project
            )
            withFirst = project
            try ProjectEditing.apply(ProjectMutations.appendNode(first, to: project), to: &withFirst)
            try ProjectEditing.apply(
                ProjectMutations.setCanvasPoint(CanvasPoint(x: 120, y: 120), for: first.id, in: withFirst),
                to: &withFirst
            )
        } catch {
            assertionFailure("新建项目的内置操作失败：\(error)")
            errorMessage = error.localizedDescription
            return
        }
        let issues = ProjectValidator.issues(in: withFirst)
        assert(issues.isEmpty, "新建项目不应有校验问题：\(issues)")
        // 立刻落一份草稿：没选位置也要先保住内容。
        let draftURL: URL?
        do {
            draftURL = try DraftStore.makeDraft(from: withFirst).url
        } catch {
            assertionFailure("新建项目草稿写入失败：\(error)")
            errorMessage = error.localizedDescription
            draftURL = nil
        }
        open(project: withFirst, at: draftURL)
        isDraft = draftURL != nil
        selectedNodeID = first.id
    }

    func open(project: StoryProject, at url: URL?) {
        // 换工程：断开上一个工程的自动保存与写盘回调。
        autosaveTask?.cancel()
        autosaveTask = nil
        saveInFlight = nil
        saveFlightID = nil
        sessionToken = UUID()
        saveGeneration += 1
        pendingAssets = [:]
        editRevision = 0
        savedRevision = 0
        isDraft = url.map { $0.path.hasPrefix(DraftStore.directory.path) } ?? false
        let editor = StoryEditor(project: project)
        self.editor = editor
        self.packageURL = url
        self.warnings = ProjectValidator.issues(in: project)
        self.saveState = .idle
        self.lastStamp = url.flatMap { ProjectPackage.stamp(in: $0) }
        self.hasSaveConflict = false
        self.conflictMessage = nil
        refreshUndoAvailability()
        refreshDerived()
        // 上次写到哪一场就选哪一场；写作模式重开后能接着写。
        let resume = lastWritingSceneID().flatMap { id in
            project.node(id).flatMap { $0.status == .draft ? $0.id : nil }
        }
        self.selectedNodeID = resume ?? project.nodes.first?.id
        if let resume, let node = project.node(resume) {
            self.focusedChapterID = node.chapterID ?? project.chapters.first?.id
        } else {
            self.focusedChapterID = project.chapters.first?.id
        }
        // 讨论记录随包存；重开接上最近一次，AI 面板不会空着。
        self.aiDiscussionID = project.discussions.last(where: { $0.anchorNodeID == self.selectedNodeID })?.id
            ?? project.discussions.last?.id
        if let url, !isDraft {
            remember(url)
        }
    }

    func openExisting(at url: URL) {
        do {
            let loaded = try ProjectPackage.load(from: url)
            open(project: loaded.project, at: url)
            warnings = loaded.warnings
            if loaded.recoveredFromPreviousVersion {
                errorMessage = InterfaceLanguage.label("project.json 损坏，已打开上一版本。")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 文件菜单用：先存旧项目，再开新的。没存成功就不换。
    func requestNewProject(useSample: Bool) {
        Task {
            guard await saveBeforeSwitching() else { return }
            newProject(useSample: useSample)
        }
    }

    /// 换工程前先把旧工程存住；取消、失败、冲突都拦下这次切换。
    func saveBeforeSwitching() async -> Bool {
        guard isOpen else { return true }
        // 保存期间作者还能继续打字：每轮写盘回来先提交等待中的文本，再核对版本。
        for _ in 0 ..< 3 {
            commitAllTextDrafts()
            let outcome = isDraft ? await autosave() : await save()
            guard outcome.isSaved else { return false }
            commitAllTextDrafts()
            if editRevision == savedRevision { return true }
        }
        commitAllTextDrafts()
        return editRevision == savedRevision
    }

    func openWithPanel() {
        Task {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            // .causal 是包（目录），不这样设的话在面板里会被当成文件而点不中。
            panel.treatsFilePackagesAsDirectories = true
            panel.message = InterfaceLanguage.label("选一个 .causal 工程包")
            panel.prompt = InterfaceLanguage.label("打开")
            panel.directoryURL = recentProjects.first?.deletingLastPathComponent()
            guard let url = await FilePanels.url(panel) else { return }
            guard await saveBeforeSwitching() else { return }
            openExisting(at: url)
        }
    }

    /// 从访达双击、拖到 Dock 图标或 `open -a` 进来的工程包。先存旧项目再换。
    func openProjectFromFinder(_ url: URL) {
        Task {
            guard await saveBeforeSwitching() else { return }
            openExisting(at: url)
        }
    }

    func requestClose() {
        Task {
            guard await saveBeforeSwitching() else { return }
            guard !hasSaveConflict else { return }
            close()
        }
    }

    func close() {
        // 关掉之后到达的写盘回调不再属于任何工程。
        sessionToken = UUID()
        saveGeneration += 1
        saveInFlight = nil
        saveFlightID = nil
        editRevision = 0
        savedRevision = 0
        for task in textDraftTasks.values { task.cancel() }
        textDraftTasks = [:]
        textDrafts = [:]
        autosaveTask?.cancel()
        canUndo = false
        canRedo = false
        lastStamp = nil
        hasSaveConflict = false
        conflictMessage = nil
        editor = nil
        packageURL = nil
        selectedNodeID = nil
        outlines = []
        projectIndex = nil
        writingScenes = []
        isWriting = false
        isAuditing = false
        isSynopsizing = false
        isThreading = false
        focusedThreadID = nil
        isPlaying = false
        playthrough = nil
        synopsisGroups = []
        synopsisPolish = [:]
        synopsisPolishErrors = [:]
        synopsisPolishing = []
        auditTask?.cancel()
        auditFindings = []
        auditWaivedFindings = []
        wordCounts = .empty
        pendingAssets = [:]
        warnings = []
        saveState = .idle
    }

    // MARK: 编辑

    /// 模型内容的版本号 +1。保存与切工程前靠它确认最后一笔已经落盘。
    func markEdited() {
        editRevision += 1
    }

    func apply(_ operations: [EditOperation], name: String, coalescingKey: String? = nil) {
        guard let editor, !operations.isEmpty else { return }
        do {
            try editor.apply(operations, name: name, coalescingKey: coalescingKey)
            markEdited()
            refreshUndoAvailability()
            refreshDerived()
            saveState = .dirty
            scheduleAutosave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undo() {
        commitAllTextDrafts()
        guard let editor else { return }
        do {
            try editor.undo()
            markEdited()
            refreshUndoAvailability()
            refreshDerived()
            saveState = .dirty
            scheduleAutosave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func redo() {
        commitAllTextDrafts()
        guard let editor else { return }
        do {
            try editor.redo()
            markEdited()
            refreshUndoAvailability()
            refreshDerived()
            saveState = .dirty
            scheduleAutosave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateNode(_ id: NodeID, coalescingKey: String? = nil, _ body: @escaping (inout StoryNode) -> Void) {
        guard let project else { return }
        apply(ProjectMutations.updateNode(id, in: project, body), name: "修改场景", coalescingKey: coalescingKey)
    }

    func addNode(title: String = InterfaceLanguage.label("新场景"), kind: NodeKind = .event) {
        guard let project else { return }
        let chapterID = focusedChapterID ?? project.chapters.first?.id
        let node = StoryNode(
            kind: kind,
            title: title,
            summary: "",
            chapterID: chapterID,
            isEntry: project.nodes.isEmpty
        )
        var operations = ProjectMutations.appendNode(node, to: project)
        operations += ProjectMutations.setCanvasPoint(nextCanvasPoint(), for: node.id, in: project)
        apply(operations, name: "新建场景")
        selectedNodeID = node.id
    }

    func addChapter() {
        guard let project else { return }
        let chapter = Chapter(title: String(format: InterfaceLanguage.label("第%lld章"), project.chapters.count + 1))
        apply(ProjectMutations.appendChapter(chapter, to: project), name: "新建章节")
        focusedChapterID = chapter.id
    }

    func addIdeaCard() {
        guard let project else { return }
        let node = StoryNode(status: .idea, title: InterfaceLanguage.label("灵感"))
        apply(ProjectMutations.appendNode(node, to: project), name: "新建灵感卡")
        selectedNodeID = node.id
    }

    func connect(from: NodeID, to: NodeID, kind: EdgeKind, label: String, condition: String) {
        guard let project else { return }
        apply(
            ProjectMutations.connect(
                from: from,
                to: to,
                kind: kind,
                label: label,
                condition: condition,
                in: project
            ),
            name: "连线"
        )
    }

    func moveCanvasNode(_ id: NodeID, to point: CanvasPoint) {
        guard let project else { return }
        apply(
            ProjectMutations.setCanvasPoint(point, for: id, in: project),
            name: "移动卡片",
            coalescingKey: "canvas:\(id)"
        )
    }

    // MARK: 配图

    func importImage(from url: URL, for nodeID: NodeID) {
        guard let project else { return }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = String(format: InterfaceLanguage.label("读取图片失败：%@"), url.lastPathComponent)
            return
        }
        Task {
            let size = await ThumbnailService.shared.pixelSize(of: url)
            let ext = url.pathExtension.lowercased().isEmpty ? "png" : url.pathExtension.lowercased()
            let asset = Asset(
                fileName: "\(AssetID().rawValue.uuidString).\(ext)",
                sha256: Digest.sha256Hex(data),
                byteCount: data.count,
                pixelWidth: Int(size?.width ?? 0),
                pixelHeight: Int(size?.height ?? 0),
                caption: url.deletingPathExtension().lastPathComponent
            )
            pendingAssets[asset.id] = data
            var operations = ProjectMutations.appendAsset(asset, to: project)
            operations += ProjectMutations.attachCover(asset.id, to: nodeID, in: project)
            apply(operations, name: "添加配图")
        }
    }

    // MARK: 保存

    /// 自动保存只在项目已经有存放位置时进行；草稿写回草稿，未命名项目不弹保存面板。
    func scheduleAutosave() {
        autosaveTask?.cancel()
        guard packageURL != nil else { return }
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.autosave()
        }
    }

    /// 自动保存：只写回当前包，草稿也写回草稿。从不弹面板。
    @discardableResult
    private func autosave() async -> SaveOutcome {
        commitAllTextDrafts()
        guard let project, let url = packageURL else { return .cancelled }
        return await write(
            project,
            to: renamePackageIfNeeded(for: project.title) ?? url,
            expecting: lastStamp
        )
    }

    /// 手动保存（⌘S、换工程、关窗前）。返回值告诉调用方能不能接着换工程。
    @discardableResult
    func save() async -> SaveOutcome {
        autosaveTask?.cancel()
        // 防抖里的文字先落进模型，快照才是作者眼前的这一版。
        commitAllTextDrafts()
        var outcome = await runSaveFlight()
        var catchUp = 0
        while outcome.isSaved {
            // 写盘期间新打的字先在模型里落定，再核对这一版有没有落盘。
            commitAllTextDrafts()
            guard editRevision != savedRevision, catchUp < 2 else { break }
            outcome = await runSaveFlight()
            catchUp += 1
        }
        return outcome
    }

    /// 同一时间只跑一次保存：正在存的时候再存，等的是同一笔结果。
    private func runSaveFlight() async -> SaveOutcome {
        if let inFlight = saveInFlight {
            return await inFlight.value
        }
        let id = UUID()
        saveFlightID = id
        let task = Task { [weak self] in
            guard let self else { return SaveOutcome.cancelled }
            return await self.performSave()
        }
        saveInFlight = task
        let outcome = await task.value
        if saveFlightID == id {
            saveInFlight = nil
            saveFlightID = nil
        }
        return outcome
    }

    private func performSave() async -> SaveOutcome {
        commitAllTextDrafts()
        guard let project else { return .cancelled }
        let token = sessionToken
        let stamp = lastStamp
        if isDraft, let draft = packageURL {
            // 草稿第一次保存：先写回草稿，再整包搬到作者选的位置。
            guard let chosen = await chooseSaveLocation(defaultName: project.title) else { return .cancelled }
            guard token == sessionToken else { return .cancelled }
            return await adoptDraft(project, draft: draft, to: chosen, expecting: stamp)
        }
        let target: URL
        if let existing = packageURL {
            target = renamePackageIfNeeded(for: project.title) ?? existing
        } else {
            guard let chosen = await chooseSaveLocation(defaultName: project.title) else { return .cancelled }
            guard token == sessionToken else { return .cancelled }
            target = chosen
        }
        guard token == sessionToken else { return .cancelled }
        return await write(project, to: target, expecting: stamp)
    }

    /// 草稿转正：内容先写进草稿包，再整包搬到目标位置。搬成功才切换 packageURL。
    private func adoptDraft(
        _ project: StoryProject,
        draft: URL,
        to chosen: URL,
        expecting: PackageStamp?
    ) async -> SaveOutcome {
        saveGeneration += 1
        let generation = saveGeneration
        let token = sessionToken
        let revision = editRevision
        let assets = pendingAssets
        saveState = .saving
        do {
            let report = try await saveQueue.save(project, to: draft, assets: assets, expecting: expecting)
            guard generation == saveGeneration, token == sessionToken else { return .cancelled }
            try DraftStore.adopt(draft, to: chosen)
            clearPendingAssets(report, assets: assets)
            packageURL = chosen
            isDraft = false
            lastStamp = ProjectPackage.stamp(in: chosen)
            hasSaveConflict = false
            conflictMessage = nil
            rememberIfReal(chosen)
            applyMissingAssets(report, project: project)
            savedRevision = revision
            saveState = .saved(Date())
            return .saved
        } catch {
            return failWrite(error, generation: generation, token: token)
        }
    }

    /// 保存时把包名对齐到标题，跟 macOS 文档改名一个手感。目标重名就加序号。
    private func renamePackageIfNeeded(for title: String) -> URL? {
        guard let current = packageURL, !isDraft else { return packageURL }
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !safe.isEmpty else { return current }

        let folder = current.deletingLastPathComponent()
        var destination = folder.appendingPathComponent("\(safe).\(ProjectPackage.fileExtension)", isDirectory: true)
        var index = 2
        while destination.path != current.path, FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(safe) \(index).\(ProjectPackage.fileExtension)", isDirectory: true)
            index += 1
        }
        guard destination.path != current.path else { return current }
        guard (try? FileManager.default.moveItem(at: current, to: destination)) != nil else { return current }

        forget(current)
        packageURL = destination
        lastStamp = ProjectPackage.stamp(in: destination)
        remember(destination)
        return destination
    }

    /// 关窗、退出时用：不走 await、不开面板，写完再让进程走。
    /// 自动保存是 1 秒防抖，刚敲完一句就关窗的话，这一下会把最后一句接上。
    func saveNow() {
        commitAllTextDrafts()
        autosaveTask?.cancel()
        guard let project, let url = packageURL else { return }
        writeSync(project, to: url)
    }

    /// 主线程只拍快照，编码与写盘交给 SaveQueue。
    /// 写盘成功且这次写仍属于当前工程，才更新 packageURL 与保存状态。
    @discardableResult
    private func write(
        _ project: StoryProject,
        to url: URL,
        expecting: PackageStamp?,
        copyingAssetsFrom source: URL? = nil
    ) async -> SaveOutcome {
        saveGeneration += 1
        let generation = saveGeneration
        let token = sessionToken
        let revision = editRevision
        let assets = pendingAssets
        saveState = .saving
        do {
            let report = try await saveQueue.save(
                project,
                to: url,
                assets: assets,
                expecting: expecting,
                copyingAssetsFrom: source
            )
            return finishWrite(
                report,
                project: project,
                url: url,
                assets: assets,
                generation: generation,
                token: token,
                revision: revision
            )
        } catch {
            return failWrite(error, generation: generation, token: token)
        }
    }

    @discardableResult
    private func finishWrite(
        _ report: SaveReport,
        project: StoryProject,
        url: URL,
        assets: [AssetID: Data],
        generation: Int,
        token: UUID,
        revision: Int
    ) -> SaveOutcome {
        // 工程已经换了：这次写的是上一个工程的包，状态不能落到当前会话。
        guard token == sessionToken else { return .cancelled }
        // 后面还有更新的一次写，让它来更新状态。
        guard generation == saveGeneration else { return .cancelled }
        clearPendingAssets(report, assets: assets)
        packageURL = url
        lastStamp = ProjectPackage.stamp(in: url)
        hasSaveConflict = false
        conflictMessage = nil
        rememberIfReal(url)
        applyMissingAssets(report, project: project)
        savedRevision = revision
        saveState = .saved(Date())
        return .saved
    }

    @discardableResult
    private func failWrite(_ error: any Error, generation: Int, token: UUID) -> SaveOutcome {
        guard token == sessionToken else { return .cancelled }
        guard generation == saveGeneration else { return .cancelled }
        let message = error.localizedDescription
        if let packageError = error as? PackageError, case .conflict = packageError {
            handleSaveConflict(packageError)
            return .conflict(message)
        }
        saveState = .failed(message)
        errorMessage = message
        return .failed(message)
    }

    private func clearPendingAssets(_ report: SaveReport, assets: [AssetID: Data]) {
        let landed = report.writtenAssetIDs + report.copiedAssetIDs + report.reusedAssetIDs
        for id in landed where assets[id] != nil {
            pendingAssets[id] = nil
        }
    }

    private func applyMissingAssets(_ report: SaveReport, project: StoryProject) {
        warnings = report.missingAssetIDs.compactMap { id in
            project.asset(id).map {
                String(format: InterfaceLanguage.label("配图未落盘：%@"), $0.fileName)
            }
        }
    }

    private func handleSaveConflict(_ error: any Error) {
        autosaveTask?.cancel()
        let message = error.localizedDescription
        conflictMessage = message
        saveState = .failed(message)
        hasSaveConflict = true
    }

    /// 关窗时遇到冲突：窗口马上走，把本机内容留成一份草稿，下次启动能找回。
    /// 草稿要带齐内存里刚加的图和原包已存的图，否则重开只剩引用。
    private func preserveConflictCopy(_ project: StoryProject, error: any Error) {
        let message = error.localizedDescription
        saveState = .failed(message)
        do {
            let draft = try DraftStore.makeDraft(
                from: project,
                newAssetData: pendingAssets,
                copyingAssetsFrom: packageURL
            )
            var note = message + "\n" + String(
                format: InterfaceLanguage.label("本机改动已存成草稿：%@"),
                draft.url.lastPathComponent
            )
            if !draft.missingAssetFileNames.isEmpty {
                note += "\n" + String(
                    format: InterfaceLanguage.label("这些配图没能写进草稿：%@"),
                    draft.missingAssetFileNames.joined(separator: InterfaceLanguage.listSeparator)
                )
            }
            conflictMessage = note
        } catch {
            conflictMessage = message
        }
    }

    /// 关窗、退出用：同步写完再让进程走。
    private func writeSync(_ project: StoryProject, to url: URL) {
        saveGeneration += 1
        let revision = editRevision
        saveState = .saving
        do {
            let report = try ProjectPackage.save(
                project,
                to: url,
                newAssetData: pendingAssets,
                expecting: lastStamp
            )
            for id in report.writtenAssetIDs + report.copiedAssetIDs + report.reusedAssetIDs {
                pendingAssets[id] = nil
            }
            packageURL = url
            lastStamp = ProjectPackage.stamp(in: url)
            rememberIfReal(url)
            applyMissingAssets(report, project: project)
            savedRevision = revision
            saveState = .saved(Date())
        } catch {
            if let packageError = error as? PackageError, case .conflict = packageError {
                preserveConflictCopy(project, error: packageError)
            } else {
                saveState = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    func beginRenameProject() {
        renameDraft = project?.title ?? ""
        showingRename = true
    }

    func commitRenameProject() {
        showingRename = false
        guard let project else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        apply(ProjectMutations.updateHeader(title: trimmed, in: project), name: "改项目名")
    }

    func clearErrorHistory() {
        errorHistory.removeAll()
    }

    /// 保存失败后重试：不动编辑状态，直接再写一次。
    func retrySave() {
        guard !hasSaveConflict else { return }
        Task {
            guard let project, let url = packageURL else {
                _ = await save()
                return
            }
            errorMessage = nil
            _ = await write(project, to: url, expecting: lastStamp)
        }
    }

    // MARK: 并发冲突

    func dismissSaveConflict() {
        hasSaveConflict = false
    }

    /// 保住两边的改动：本机内容另存成一个新包。旧包的图一起搬过去，写成功才离开冲突。
    func resolveConflictBySavingAs() {
        Task {
            guard let project else { return }
            guard let url = await chooseSaveLocation(defaultName: project.title) else { return }
            let outcome = await write(
                project,
                to: url,
                expecting: nil,
                copyingAssetsFrom: packageURL
            )
            guard outcome.isSaved else { return }
            hasSaveConflict = false
            conflictMessage = nil
        }
    }

    /// 明确以本机内容覆盖磁盘。
    func resolveConflictByOverwriting() {
        guard let project, let url = packageURL else {
            hasSaveConflict = false
            return
        }
        hasSaveConflict = false
        Task {
            _ = await write(project, to: url, expecting: nil)
        }
    }

    /// 放弃本机改动，重新读磁盘。按钮上已经写明会丢本机改动。
    func resolveConflictByReloadingDisk() {
        guard let url = packageURL else {
            hasSaveConflict = false
            return
        }
        hasSaveConflict = false
        openExisting(at: url)
    }

    /// 另存为一个新包。旧包里已有的配图一起复制，新包写成功才切当前路径。
    func saveAs() {
        Task {
            commitAllTextDrafts()
            guard let project else { return }
            guard let url = await chooseSaveLocation(defaultName: project.title) else { return }
            let source = packageURL
            let wasDraft = isDraft
            let outcome = await write(
                project,
                to: url,
                expecting: nil,
                copyingAssetsFrom: source
            )
            guard outcome.isSaved else { return }
            if wasDraft {
                isDraft = false
                if let source { _ = DraftStore.discard(source) }
            }
        }
    }

    func exportMarkdown() {
        Task {
            commitAllTextDrafts()
            guard let project else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            let route = activeRoute
            let suffix = route.flatMap { project.node($0.endingID)?.title } ?? ""
            panel.nameFieldStringValue = suffix.isEmpty
                ? "\(project.title).md"
                : "\(project.title)-\(workLanguage.label("通往"))\(suffix).md"
            guard let url = await FilePanels.url(panel) else { return }
            do {
                let report = try MarkdownExport.write(
                    project: project,
                    route: route,
                    packageURL: packageURL,
                    to: url,
                    label: workLanguage.label
                )
                if !report.missingAssetFileNames.isEmpty {
                    errorMessage = InterfaceLanguage.label("这些配图没能一起导出，Markdown 里的引用会是空白：")
                        + report.missingAssetFileNames.joined(separator: InterfaceLanguage.listSeparator)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 故事图导出成 PNG（2x）。
    func exportCanvasImage() {
        Task { @MainActor in
            commitAllTextDrafts()
            guard let project,
                  let data = CanvasImageExport.makePNG(project: project, language: workLanguage) else {
                errorMessage = InterfaceLanguage.label("故事图里还没有卡片")
                return
            }
            let rects = CanvasImageExport.layout(project)
            let bounds = rects.values.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -56, dy: -56)
            let used = CanvasImageExport.scale(for: bounds.size)
            if used < 1 {
                warnings.append(String(format: InterfaceLanguage.label("故事图尺寸较大，已按 %.2f 倍导出（长边上限 8000 像素）。"), used))
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "\(project.title)-\(workLanguage.label("故事图")).png"
            guard let url = await FilePanels.url(panel) else { return }
            do {
                try data.write(to: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 开发用：不弹面板直接导出故事图，方便命令行核对产物。
    @MainActor
    func debugExportCanvas(to path: String) {
        guard let project, let data = CanvasImageExport.makePNG(project: project, language: workLanguage) else {
            print("[export] 没东西可导")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("[export] 写出 \(path)（\(data.count) 字节）")
        } catch {
            print("[export] 失败：\(error)")
        }
    }

    /// 大纲导出成 A4 分页 PDF，跟随当前的路线筛选。
    func exportOutlinePDF() {
        Task { @MainActor in
            commitAllTextDrafts()
            guard let project else { return }
            let route = activeRoute
            guard let data = OutlinePDFExport.makePDF(project: project, route: route, packageURL: packageURL, language: workLanguage) else {
                errorMessage = InterfaceLanguage.label("没有可导出的大纲")
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            let suffix = route.flatMap { project.node($0.endingID)?.title } ?? ""
            panel.nameFieldStringValue = suffix.isEmpty
                ? "\(project.title).pdf"
                : "\(project.title)-\(workLanguage.label("通往"))\(suffix).pdf"
            guard let url = await FilePanels.url(panel) else { return }
            do {
                try data.write(to: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 开发用：直接写 PDF，不弹面板。
    @MainActor
    func debugExportPDF(to path: String) {
        guard let project, let data = OutlinePDFExport.makePDF(
            project: project,
            route: activeRoute,
            packageURL: packageURL,
            language: workLanguage
        ) else {
            print("[export] 没有可导出的大纲")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("[export] 写出 \(path)（\(data.count) 字节）")
        } catch {
            print("[export] 失败：\(error)")
        }
    }

    private func chooseSaveLocation(defaultName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(defaultName).\(ProjectPackage.fileExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return await FilePanels.url(panel)
    }

    /// 菜单里的撤销/重做是否可用。
    func refreshUndoAvailability() {
        canUndo = editor?.canUndo ?? false
        canRedo = editor?.canRedo ?? false
    }

    func refreshDerived() {
        guard let project else {
            outlines = []
            projectIndex = nil
            writingScenes = []
            wordCounts = .empty
            mainline = .empty
            return
        }
        let index = project.makeIndex()
        projectIndex = index
        wordCounts = WordCount.Book(project: project)
        writingScenes = WritingOrder.scenes(in: project)
        outlines = OutlineBuilder.build(project: project, index: index)
        mainline = Mainline.derive(in: project)
        refreshAudit()
    }

    var auditErrorCount: Int { auditFindings.count { $0.severity == .error } }
    var auditWarningCount: Int { auditFindings.count { $0.severity == .warning } }
    var auditInfoCount: Int { auditFindings.count { $0.severity == .info } }

    func chapterTitle(_ id: ChapterID?) -> String {
        guard let id, let project else { return "未分章" }
        return project.chapter(id)?.title ?? "未分章"
    }

    var searchResults: [(node: StoryNode, chapterTitle: String)] {
        guard let project else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let index = projectIndex ?? project.makeIndex()
        return project.nodes
            .filter { node in
                node.title.localizedCaseInsensitiveContains(query)
                    || node.summary.localizedCaseInsensitiveContains(query)
                    || node.body.localizedCaseInsensitiveContains(query)
                    || node.characterIDs.contains { characterID in
                        index.characterByID[characterID]?.name.localizedCaseInsensitiveContains(query) == true
                    }
                    || node.placeIDs.contains { placeID in
                        index.placeByID[placeID]?.name.localizedCaseInsensitiveContains(query) == true
                    }
            }
            .map { (node: $0, chapterTitle: chapterTitle($0.chapterID)) }
    }

    // MARK: 画布

    private func nextCanvasPoint() -> CanvasPoint {
        guard let project else { return .zero }
        let count = project.nodes.count
        return CanvasPoint(x: 160 + Double(count % 5) * 260, y: 160 + Double(count / 5) * 260)
    }

    func canvasPoint(for node: StoryNode) -> CanvasPoint {
        project?.canvas[node.id] ?? CanvasPoint(x: 0, y: 0)
    }

    // MARK: 最近项目

    var recentProjects: [URL] {
        recents.filter { !$0.path.hasPrefix(DraftStore.directory.path) }
    }

    private var recents: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        // 已经删掉的包不要留在列表里（打开失败、点不动）。
        let alive = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if alive.count != paths.count {
            UserDefaults.standard.set(alive.map(\.path), forKey: Self.recentsKey)
        }
        return alive
    }

    private func forget(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        paths.removeAll { $0 == url.path }
        UserDefaults.standard.set(paths, forKey: Self.recentsKey)
    }

    private func remember(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(8)), forKey: Self.recentsKey)
    }

    /// 草稿包不进“最近打开”，起始页已经有单独的草稿列表。
    private func rememberIfReal(_ url: URL) {
        guard !url.path.hasPrefix(DraftStore.directory.path) else { return }
        remember(url)
    }
}

enum AIState: Equatable {
    case idle
    case waiting
    case streaming(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .waiting, .streaming: true
        case .idle, .failed: false
        }
    }

    var displayText: String {
        switch self {
        case .idle: ""
        case .waiting: "等待首个字…"
        case let .streaming(text): text
        case let .failed(message): String(format: InterfaceLanguage.label("失败：%@"), message)
        }
    }
}
