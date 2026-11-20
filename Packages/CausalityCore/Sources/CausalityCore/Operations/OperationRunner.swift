import Foundation

/// 一条操作执行完的结果。失败会抛 `ScriptError`，成功时这里只有可用的线索。
public struct ScriptResult: Sendable, Equatable {
    public var index: Int
    public var op: String
    public var detail: String
    /// 新建对象的 UUID，方便下一条操作直接引用。
    public var createdID: String?

    public init(index: Int, op: String, detail: String, createdID: String? = nil) {
        self.index = index
        self.op = op
        self.detail = detail
        self.createdID = createdID
    }
}

public struct ScriptError: Error, CustomStringConvertible, LocalizedError {
    public var index: Int
    public var op: String
    public var reason: String

    public init(index: Int, op: String, reason: String) {
        self.index = index
        self.op = op
        self.reason = reason
    }

    public var description: String {
        CoreText.format("第 %lld 条 %@ 失败：%@", index + 1, op, reason)
    }

    public var errorDescription: String? { description }
}

/// 按顺序把脚本落到工程上。任何一条失败都停下，已执行的部分留在 `project` 里，
/// 由调用方决定要不要保存。
/// 引用解析失败。由调用方补上「第几条、哪个 op」。
private struct ResolveFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

public enum OperationRunner {
    public static func apply(_ script: OperationScript, to project: inout StoryProject) throws -> [ScriptResult] {
        var results: [ScriptResult] = []
        for (index, op) in script.ops.enumerated() {
            do {
                let result = try perform(op, index: index, on: &project)
                results.append(result)
            } catch let error as ScriptError {
                throw error
            } catch {
                throw ScriptError(index: index, op: op.name, reason: "\(error)")
            }
        }
        return results
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func perform(_ op: ScriptOp, index: Int, on project: inout StoryProject) throws -> ScriptResult {
        switch op {
        case let .updateHeader(title, logline):
            try apply(ProjectMutations.updateHeader(title: title, logline: logline, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.text("更新项目头"))

        case let .arrangeCanvas(columns):
            let operations = CanvasLayout.arrange(project: project, columns: columns ?? CanvasLayout.defaultColumns)
            try apply(operations, to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("重排 %lld 张卡", operations.count / 2))

        case let .addChapter(title, summary):
            let chapter = Chapter(title: title, summary: summary ?? "")
            try apply(ProjectMutations.appendChapter(chapter, to: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("新建章节「%@」", title), createdID: chapter.id.rawValue.uuidString)

        case let .updateChapter(ref, title, summary):
            let id = try chapterID(ref, in: project)
            let ops = ProjectMutations.updateChapter(id, in: project) { chapter in
                if let title { chapter.title = title }
                if let summary { chapter.summary = summary }
            }
            try apply(ops, to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("改章节「%@」", title ?? ref))

        case let .deleteChapter(ref):
            let id = try chapterID(ref, in: project)
            try apply(ProjectMutations.deleteChapter(id, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("删章节「%@」", ref))

        case let .addCard(draft):
            return try addCard(draft, index: index, on: &project)

        case let .updateCard(ref, patch):
            return try updateCard(ref: ref, patch: patch, index: index, on: &project)

        case let .moveCard(ref, chapterRef, targetIndex):
            let id = try nodeID(ref, in: project)
            let chapter: ChapterID?
            if let chapterRef {
                chapter = try chapterID(chapterRef, in: project)
            } else {
                chapter = project.node(id)?.chapterID
            }
            guard let chapter else {
                throw ScriptError(index: index, op: op.name, reason: CoreText.format("「%@」没有所属章节，moveCard 需要 chapter", ref))
            }
            try apply(ProjectMutations.moveCard(id, toChapter: chapter, at: targetIndex ?? Int.max, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("移动卡片「%@」", ref))

        case let .deleteCard(ref):
            let id = try nodeID(ref, in: project)
            try apply(ProjectMutations.deleteNode(id, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("删卡片「%@」", ref))

        case let .setEntry(ref, isEntry):
            let id = try nodeID(ref, in: project)
            try apply(ProjectMutations.setEntry(id, isEntry: isEntry, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: isEntry ? CoreText.format("故事入口 开：「%@」", ref) : CoreText.format("故事入口 关：「%@」", ref))

        case let .connect(from, to, kind, label, condition, mainline):
            let start = try nodeID(from, in: project)
            let end = try nodeID(to, in: project)
            let before = Set(project.edges.map(\.id))
            try apply(ProjectMutations.connect(
                from: start,
                to: end,
                kind: kind ?? .plain,
                label: label ?? "",
                condition: condition ?? "",
                in: project
            ), to: &project)
            guard let edge = project.edges.first(where: { !before.contains($0.id) }) else {
                throw ScriptError(index: index, op: op.name, reason: CoreText.text("连线没有落下"))
            }
            if mainline == true {
                try apply(ProjectMutations.setMainline(edge.id, in: project), to: &project)
            }
            return ScriptResult(
                index: index,
                op: op.name,
                detail: CoreText.format("连线「%@」→「%@」", from, to),
                createdID: edge.id.rawValue.uuidString
            )

        case let .updateEdge(ref, label, condition, kind, mainline):
            let id = try edgeID(ref, in: project)
            try apply(ProjectMutations.updateEdge(id, in: project) { edge in
                if let label { edge.label = label }
                if let condition { edge.condition = condition }
                if let kind { edge.kind = kind }
            }, to: &project)
            if let mainline {
                let ops = mainline
                    ? ProjectMutations.setMainline(id, in: project)
                    : ProjectMutations.clearMainline(id, in: project)
                try apply(ops, to: &project)
            }
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("改连线「%@」", ref))

        case let .deleteEdge(ref):
            let id = try edgeID(ref, in: project)
            try apply(ProjectMutations.disconnect(id, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("删连线「%@」", ref))

        case let .addCharacter(name, summary, notes):
            let character = StoryCharacter(name: name, summary: summary ?? "", notes: notes ?? "")
            try apply(ProjectMutations.appendCharacter(character, to: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("新建人物「%@」", name), createdID: character.id.rawValue.uuidString)

        case let .updateCharacter(ref, name, summary, notes):
            let id = try characterID(ref, in: project)
            try apply(ProjectMutations.updateCharacter(id, in: project) { character in
                if let name { character.name = name }
                if let summary { character.summary = summary }
                if let notes { character.notes = notes }
            }, to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("改人物「%@」", ref))

        case let .deleteCharacter(ref):
            let id = try characterID(ref, in: project)
            try apply(ProjectMutations.deleteCharacter(id, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("删人物「%@」", ref))

        case let .addRelation(from, to, kind):
            let source = try characterID(from, in: project)
            let target = try characterID(to, in: project)
            try apply(ProjectMutations.addRelation(kind, from: source, to: target, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: "\(from) —\(kind.rawValue)→ \(to)")

        case let .addPlace(name, summary, notes):
            let place = StoryPlace(name: name, summary: summary ?? "", notes: notes ?? "")
            try apply(ProjectMutations.appendPlace(place, to: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("新建地点「%@」", name), createdID: place.id.rawValue.uuidString)

        case let .updatePlace(ref, name, summary, notes):
            let id = try placeID(ref, in: project)
            try apply(ProjectMutations.updatePlace(id, in: project) { place in
                if let name { place.name = name }
                if let summary { place.summary = summary }
                if let notes { place.notes = notes }
            }, to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("改地点「%@」", ref))

        case let .addSetting(title, text, confirmed, locked):
            let setting = Setting(title: title, text: text ?? "")
            try apply(ProjectMutations.appendSetting(setting, to: project), to: &project)
            if confirmed != nil { try setSetting(setting.id, confirmed: confirmed, locked: nil, index: index, project: &project) }
            if locked != nil { try setSetting(setting.id, confirmed: nil, locked: locked, index: index, project: &project) }
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("新建事实设定「%@」", title), createdID: setting.id.rawValue.uuidString)

        case let .updateSetting(ref, title, text, confirmed, locked):
            let id = try settingID(ref, in: project)
            try apply(ProjectMutations.updateSetting(id, in: project) { setting in
                if let title { setting.title = title }
                if let text { setting.text = text }
            }, to: &project)
            try setSetting(id, confirmed: confirmed, locked: locked, index: index, project: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("改事实设定「%@」", ref))

        case let .attachSetting(settingRef, cardRef):
            let setting = try settingID(settingRef, in: project)
            let card = try nodeID(cardRef, in: project)
            try apply(ProjectMutations.attachSetting(setting, to: card, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("「%@」挂到「%@」", settingRef, cardRef))

        case let .detachSetting(settingRef, cardRef):
            let setting = try settingID(settingRef, in: project)
            let card = try nodeID(cardRef, in: project)
            try apply(ProjectMutations.detachSetting(setting, from: card, in: project), to: &project)
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("「%@」离开「%@」", settingRef, cardRef))

        case let .deleteSetting(ref):
            let id = try settingID(ref, in: project)
            do {
                try apply(ProjectMutations.deleteSetting(id, in: project), to: &project)
            } catch let error as EditError {
                throw ScriptError(index: index, op: op.name, reason: error.description)
            }
            return ScriptResult(index: index, op: op.name, detail: CoreText.format("删事实设定「%@」", ref))
        }
    }

    // MARK: - 卡片

    private static func addCard(_ draft: CardDraft, index: Int, on project: inout StoryProject) throws -> ScriptResult {
        let chapterID: ChapterID?
        if draft.status == .idea {
            chapterID = nil
        } else if let ref = draft.chapter {
            chapterID = try self.chapterID(ref, in: project)
        } else {
            chapterID = project.chapters.first?.id
        }
        if draft.status == .draft, chapterID == nil {
            throw ScriptError(index: index, op: "addCard", reason: CoreText.text("工程里还没有章节，先 addChapter"))
        }

        var node = StoryNode(
            kind: draft.kind,
            status: draft.status,
            title: draft.title,
            summary: draft.summary,
            body: draft.body,
            chapterID: chapterID,
            isEntry: draft.isEntry,
            characterIDs: try draft.characters.map { try characterID($0, in: project) },
            placeIDs: try draft.places.map { try placeID($0, in: project) }
        )

        let operations: [EditOperation]
        if let chapterID {
            let target: Int
            if let after = draft.after {
                let anchor = try nodeID(after, in: project)
                let order = project.chapter(chapterID)?.order ?? []
                target = (order.firstIndex(of: anchor) ?? order.count - 1) + 1
            } else if let explicit = draft.index {
                target = explicit
            } else {
                target = Int.max
            }
            operations = ProjectMutations.insertCard(node, in: chapterID, at: target, in: project)
        } else {
            operations = ProjectMutations.appendNode(node, to: project)
        }
        try apply(operations, to: &project)

        guard let created = project.nodes.last(where: { $0.title == node.title }) else {
            throw ScriptError(index: index, op: "addCard", reason: CoreText.text("卡片没有落下"))
        }
        node = created
        for name in draft.settings {
            let setting = try settingID(name, in: project)
            try apply(ProjectMutations.attachSetting(setting, to: node.id, in: project), to: &project)
        }
        return ScriptResult(
            index: index,
            op: "addCard",
            detail: CoreText.format("新建卡片「%@」", draft.title),
            createdID: node.id.rawValue.uuidString
        )
    }

    private static func updateCard(ref: String, patch: CardPatch, index: Int, on project: inout StoryProject) throws -> ScriptResult {
        let id = try nodeID(ref, in: project)
        guard !patch.isEmpty else {
            throw ScriptError(index: index, op: "updateCard", reason: CoreText.text("没有任何要改的字段"))
        }
        let characterIDs = try patch.characters?.map { try characterID($0, in: project) }
        let placeIDs = try patch.places?.map { try placeID($0, in: project) }

        try apply(ProjectMutations.updateNode(id, in: project) { node in
            if let title = patch.title { node.title = title }
            if let summary = patch.summary { node.summary = summary }
            if let body = patch.body { node.body = body }
            if let kind = patch.kind { node.kind = kind }
            if let status = patch.status { node.status = status }
            if let isEntry = patch.isEntry { node.isEntry = isEntry }
            if let annotation = patch.annotation { node.annotation = annotation }
            if let characterIDs { node.characterIDs = characterIDs }
            if let placeIDs { node.placeIDs = placeIDs }
        }, to: &project)

        if let chapterRef = patch.chapter {
            let chapter = try chapterID(chapterRef, in: project)
            try apply(ProjectMutations.moveCard(id, toChapter: chapter, at: Int.max, in: project), to: &project)
        }
        return ScriptResult(index: index, op: "updateCard", detail: CoreText.format("改卡片「%@」", ref))
    }

    private static func setSetting(
        _ id: SettingID,
        confirmed: Bool?,
        locked: Bool?,
        index: Int,
        project: inout StoryProject
    ) throws {
        if let confirmed {
            try apply(ProjectMutations.setSettingConfirmed(id, confirmed, in: project), to: &project)
        }
        if let locked {
            try apply(ProjectMutations.setSettingLocked(id, locked, in: project), to: &project)
        }
    }

    private static func apply(_ operations: [EditOperation], to project: inout StoryProject) throws {
        try ProjectEditing.apply(operations, to: &project)
    }

    // MARK: - 引用解析（UUID 或名字）

    private static func nodeID(_ ref: String, in project: StoryProject) throws -> NodeID {
        if let id = UUID(uuidString: ref) {
            let value = NodeID(rawValue: id)
            if project.node(value) != nil { return value }
        }
        let matches = project.nodes.filter { $0.title == ref }
        switch matches.count {
        case 1: return matches[0].id
        case 0: throw ResolveFailure(message: CoreText.format("找不到卡片「%@」", ref))
        default: throw ResolveFailure(message: CoreText.format("卡片「%@」重名，请改用 UUID：%@", ref, matches.map(\.id.rawValue.uuidString).joined(separator: ", ")))
        }
    }

    private static func chapterID(_ ref: String, in project: StoryProject) throws -> ChapterID {
        if let id = UUID(uuidString: ref), let chapter = project.chapter(ChapterID(rawValue: id)) {
            return chapter.id
        }
        let matches = project.chapters.filter { $0.title == ref }
        switch matches.count {
        case 1: return matches[0].id
        case 0: throw ResolveFailure(message: CoreText.format("找不到章节「%@」", ref))
        default: throw ResolveFailure(message: CoreText.format("章节「%@」重名，请改用 UUID", ref))
        }
    }

    private static func edgeID(_ ref: String, in project: StoryProject) throws -> EdgeID {
        if let id = UUID(uuidString: ref), let edge = project.edge(EdgeID(rawValue: id)) {
            return edge.id
        }
        let matches = project.edges.filter { $0.label == ref }
        switch matches.count {
        case 1: return matches[0].id
        case 0: throw ResolveFailure(message: CoreText.format("找不到连线「%@」，请用 UUID 或连线文字", ref))
        default: throw ResolveFailure(message: CoreText.format("连线文字「%@」有多条，请改用 UUID", ref))
        }
    }

    private static func characterID(_ ref: String, in project: StoryProject) throws -> CharacterID {
        if let id = UUID(uuidString: ref), let value = project.characters.first(where: { $0.id == CharacterID(rawValue: id) }) {
            return value.id
        }
        let matches = project.characters.filter { $0.name == ref }
        switch matches.count {
        case 1: return matches[0].id
        case 0: throw ResolveFailure(message: CoreText.format("找不到人物「%@」", ref))
        default: throw ResolveFailure(message: CoreText.format("人物「%@」重名，请改用 UUID", ref))
        }
    }

    private static func placeID(_ ref: String, in project: StoryProject) throws -> PlaceID {
        if let id = UUID(uuidString: ref), let value = project.places.first(where: { $0.id == PlaceID(rawValue: id) }) {
            return value.id
        }
        let matches = project.places.filter { $0.name == ref }
        switch matches.count {
        case 1: return matches[0].id
        case 0: throw ResolveFailure(message: CoreText.format("找不到地点「%@」", ref))
        default: throw ResolveFailure(message: CoreText.format("地点「%@」重名，请改用 UUID", ref))
        }
    }

    private static func settingID(_ ref: String, in project: StoryProject) throws -> SettingID {
        if let id = UUID(uuidString: ref), let value = project.settings.first(where: { $0.id == SettingID(rawValue: id) }) {
            return value.id
        }
        let matches = project.settings.filter { $0.title == ref }
        switch matches.count {
        case 1: return matches[0].id
        case 0: throw ResolveFailure(message: CoreText.format("找不到事实设定「%@」", ref))
        default: throw ResolveFailure(message: CoreText.format("事实设定「%@」重名，请改用 UUID", ref))
        }
    }
}
