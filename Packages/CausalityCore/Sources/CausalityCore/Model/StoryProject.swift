import Foundation

/// 一个故事项目的全部数据。这是保存进 .causal 包的元数据快照。
public struct StoryProject: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: UUID
    public var title: String
    /// 项目梗概。AI 上下文默认携带。
    public var logline: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// 内容版本号。每次编辑递增，供 AI 提案判断是否过期。
    public var revision: Int
    public var chapters: [Chapter]
    public var nodes: [StoryNode]
    public var edges: [StoryEdge]
    public var characters: [StoryCharacter]
    public var places: [StoryPlace]
    public var settings: [Setting]
    public var assets: [Asset]
    public var discussions: [Discussion]
    /// 体检里被忽略的问题。跟着包走，重开仍然忽略。
    public var auditWaivers: [AuditWaiver]
    /// 跨场线索。点内嵌在线索里，脊柱按章序渲染。
    public var threads: [StoryThread]
    /// 画布坐标表，与叙述数据分开保存。
    public var canvas: [NodeID: CanvasPoint]
    /// 人物脉络里的卡片位置。
    public var characterCanvas: [CharacterID: CanvasPoint]
    // MARK: v2a
    /// 故事板并列组的手动覆盖：键是 NodeID 字符串，值是 `mergeAbove` / `ownGroup`。
    public var cardGroupOverrides: [String: String]
    /// 当前工作路线（要看哪个结局的路径）。指向的节点被删时置空。
    public var workingRouteEndingID: NodeID?

    public static let currentSchemaVersion = 2

    /// 手写解码：新增字段缺失时按默认值补上，旧工程包还能打开。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名项目"
        logline = try container.decodeIfPresent(String.self, forKey: .logline) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Timestamp.now()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Timestamp.now()
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        nodes = try container.decodeIfPresent([StoryNode].self, forKey: .nodes) ?? []
        edges = try container.decodeIfPresent([StoryEdge].self, forKey: .edges) ?? []
        characters = try container.decodeIfPresent([StoryCharacter].self, forKey: .characters) ?? []
        places = try container.decodeIfPresent([StoryPlace].self, forKey: .places) ?? []
        settings = try container.decodeIfPresent([Setting].self, forKey: .settings) ?? []
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        discussions = try container.decodeIfPresent([Discussion].self, forKey: .discussions) ?? []
        auditWaivers = try container.decodeIfPresent([AuditWaiver].self, forKey: .auditWaivers) ?? []
        threads = try container.decodeIfPresent([StoryThread].self, forKey: .threads) ?? []
        canvas = try container.decodeIfPresent([NodeID: CanvasPoint].self, forKey: .canvas) ?? [:]
        characterCanvas = try container.decodeIfPresent([CharacterID: CanvasPoint].self, forKey: .characterCanvas) ?? [:]
        cardGroupOverrides = try container.decodeIfPresent([String: String].self, forKey: .cardGroupOverrides) ?? [:]
        workingRouteEndingID = try container.decodeIfPresent(NodeID.self, forKey: .workingRouteEndingID)
    }

    public init(
        schemaVersion: Int = StoryProject.currentSchemaVersion,
        id: UUID = UUID(),
        title: String,
        logline: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        revision: Int = 0,
        chapters: [Chapter] = [],
        nodes: [StoryNode] = [],
        edges: [StoryEdge] = [],
        characters: [StoryCharacter] = [],
        places: [StoryPlace] = [],
        settings: [Setting] = [],
        assets: [Asset] = [],
        discussions: [Discussion] = [],
        auditWaivers: [AuditWaiver] = [],
        threads: [StoryThread] = [],
        canvas: [NodeID: CanvasPoint] = [:],
        characterCanvas: [CharacterID: CanvasPoint] = [:],
        cardGroupOverrides: [String: String] = [:],
        workingRouteEndingID: NodeID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.logline = logline
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.revision = revision
        self.chapters = chapters
        self.nodes = nodes
        self.edges = edges
        self.characters = characters
        self.places = places
        self.settings = settings
        self.assets = assets
        self.discussions = discussions
        self.auditWaivers = auditWaivers
        self.threads = threads
        self.canvas = canvas
        self.characterCanvas = characterCanvas
        self.cardGroupOverrides = cardGroupOverrides
        self.workingRouteEndingID = workingRouteEndingID
    }

    public static func empty(title: String = "未命名项目") -> StoryProject {
        StoryProject(title: title)
    }

    public func makeIndex() -> ProjectIndex {
        ProjectIndex(project: self)
    }

    public func node(_ id: NodeID) -> StoryNode? {
        nodes.first { $0.id == id }
    }

    public func chapter(_ id: ChapterID) -> Chapter? {
        chapters.first { $0.id == id }
    }

    public func setting(_ id: SettingID) -> Setting? {
        settings.first { $0.id == id }
    }

    public func asset(_ id: AssetID) -> Asset? {
        assets.first { $0.id == id }
    }

    public func edge(_ id: EdgeID) -> StoryEdge? {
        edges.first { $0.id == id }
    }
}

// MARK: - 索引

/// 一次构建、多处复用的只读索引。大纲推导、画布绘制和校验都读它。
public struct ProjectIndex: Sendable {
    public let nodeByID: [NodeID: StoryNode]
    public let chapterByID: [ChapterID: Chapter]
    public let characterByID: [CharacterID: StoryCharacter]
    public let placeByID: [PlaceID: StoryPlace]
    public let settingByID: [SettingID: Setting]
    public let assetByID: [AssetID: Asset]
    public var characterCanvas: [CharacterID: CanvasPoint] = [:]
    public let outgoing: [NodeID: [StoryEdge]]
    public let incoming: [NodeID: [StoryEdge]]
    /// 节点在所属章顺序表中的位置。
    public let nodeIndexInChapter: [NodeID: Int]
    /// 章 → 按顺序表排好的卡。取卡是热路径，不能每次都 filter + sorted。
    public let chapterNodes: [ChapterID: [StoryNode]]

    public init(project: StoryProject) {
        var nodeByID: [NodeID: StoryNode] = [:]
        nodeByID.reserveCapacity(project.nodes.count)
        for node in project.nodes { nodeByID[node.id] = node }

        var chapterByID: [ChapterID: Chapter] = [:]
        for chapter in project.chapters { chapterByID[chapter.id] = chapter }

        var characterByID: [CharacterID: StoryCharacter] = [:]
        for character in project.characters { characterByID[character.id] = character }

        var placeByID: [PlaceID: StoryPlace] = [:]
        for place in project.places { placeByID[place.id] = place }

        var settingByID: [SettingID: Setting] = [:]
        for setting in project.settings { settingByID[setting.id] = setting }

        var assetByID: [AssetID: Asset] = [:]
        for asset in project.assets { assetByID[asset.id] = asset }

        var outgoing: [NodeID: [StoryEdge]] = [:]
        var incoming: [NodeID: [StoryEdge]] = [:]
        for edge in project.edges {
            outgoing[edge.from, default: []].append(edge)
            incoming[edge.to, default: []].append(edge)
        }

        var nodeIndexInChapter: [NodeID: Int] = [:]
        for chapter in project.chapters {
            for (index, nodeID) in chapter.order.enumerated() where nodeIndexInChapter[nodeID] == nil {
                nodeIndexInChapter[nodeID] = index
            }
        }

        self.nodeByID = nodeByID
        self.chapterByID = chapterByID
        self.characterByID = characterByID
        self.placeByID = placeByID
        self.settingByID = settingByID
        self.assetByID = assetByID
        self.outgoing = outgoing
        self.incoming = incoming
        self.nodeIndexInChapter = nodeIndexInChapter
        self.characterCanvas = project.characterCanvas

        var grouped: [ChapterID: [StoryNode]] = [:]
        for chapter in project.chapters {
            let orders = chapter.order.enumerated().reduce(into: [NodeID: Int]()) { result, pair in
                if result[pair.element] == nil { result[pair.element] = pair.offset }
            }
            grouped[chapter.id] = project.nodes
                .filter { $0.chapterID == chapter.id }
                .sorted { lhs, rhs in
                    let left = orders[lhs.id] ?? Int.max
                    let right = orders[rhs.id] ?? Int.max
                    if left != right { return left < right }
                    if lhs.title != rhs.title { return lhs.title < rhs.title }
                    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
                }
        }
        self.chapterNodes = grouped
    }

    public func outgoingEdges(of nodeID: NodeID) -> [StoryEdge] { outgoing[nodeID] ?? [] }

    public func incomingEdges(of nodeID: NodeID) -> [StoryEdge] { incoming[nodeID] ?? [] }

    public func nodes(in chapterID: ChapterID) -> [StoryNode] {
        chapterNodes[chapterID] ?? []
    }
}

// MARK: - 校验

/// 结构校验。保存前与 AI 提案落地前都跑一遍。
public enum ProjectValidator {
    public static func issues(in project: StoryProject) -> [String] {
        let index = project.makeIndex()
        return edgeIssues(project, index)
            + nodeIssues(project, index)
            + chapterIssues(project, index)
            + libraryIssues(project)
    }

    /// 发展线两端必须存在。
    static func edgeIssues(_ project: StoryProject, _ index: ProjectIndex) -> [String] {
        var issues: [String] = []
        for edge in project.edges {
            if index.nodeByID[edge.from] == nil {
                issues.append(CoreText.format("发展线 %@ 的起点 %@ 不存在", String(describing: edge.id), String(describing: edge.from)))
            }
            if index.nodeByID[edge.to] == nil {
                issues.append(CoreText.format("发展线 %@ 的终点 %@ 不存在", String(describing: edge.id), String(describing: edge.to)))
            }
        }
        return issues
    }

    /// 节点对其它实体的引用必须存在。
    static func nodeIssues(_ project: StoryProject, _ index: ProjectIndex) -> [String] {
        var issues: [String] = []
        for node in project.nodes {
            if let chapterID = node.chapterID, index.chapterByID[chapterID] == nil {
                issues.append(CoreText.format("节点 %@ 指向不存在的章节 %@", node.title, String(describing: chapterID)))
            }
            for id in node.characterIDs where index.characterByID[id] == nil {
                issues.append(CoreText.format("节点 %@ 引用不存在的人物 %@", node.title, String(describing: id)))
            }
            for id in node.placeIDs where index.placeByID[id] == nil {
                issues.append(CoreText.format("节点 %@ 引用不存在的地点 %@", node.title, String(describing: id)))
            }
            for id in node.settingIDs where index.settingByID[id] == nil {
                issues.append(CoreText.format("节点 %@ 引用不存在的事实设定 %@", node.title, String(describing: id)))
            }
            if let assetID = node.coverAssetID, index.assetByID[assetID] == nil {
                issues.append(CoreText.format("节点 %@ 引用不存在的配图 %@", node.title, String(describing: assetID)))
            }
        }
        return issues
    }

    /// 章内顺序表只允许本章节点，且不得重复。
    static func chapterIssues(_ project: StoryProject, _ index: ProjectIndex) -> [String] {
        var issues: [String] = []
        for chapter in project.chapters {
            var seen = Set<NodeID>()
            for nodeID in chapter.order {
                guard let node = index.nodeByID[nodeID] else {
                    issues.append(CoreText.format("章节 %@ 的顺序表包含不存在的节点 %@", chapter.title, String(describing: nodeID)))
                    continue
                }
                if node.chapterID != chapter.id {
                    issues.append(CoreText.format("章节 %@ 的顺序表包含属于其它章的节点 %@", chapter.title, node.title))
                }
                if !seen.insert(nodeID).inserted {
                    issues.append(CoreText.format("章节 %@ 的顺序表重复包含 %@", chapter.title, node.title))
                }
            }
        }
        return issues
    }

    /// 设定、配图目录之外的一致性。
    static func libraryIssues(_ project: StoryProject) -> [String] {
        var issues: [String] = []
        for setting in project.settings where setting.isLocked && !setting.isConfirmed {
            issues.append(CoreText.format("事实设定 %@ 已锁定但未确认", setting.title))
        }
        var fileNames = Set<String>()
        for asset in project.assets where !fileNames.insert(asset.fileName).inserted {
            issues.append(CoreText.format("配图文件名重复：%@", asset.fileName))
        }
        let nodeIDs = Set(project.nodes.map(\.id))
        for nodeID in project.canvas.keys where !nodeIDs.contains(nodeID) {
            issues.append(CoreText.format("画布坐标表包含不存在的节点 %@", String(describing: nodeID)))
        }
        let characterIDs = Set(project.characters.map(\.id))
        for characterID in project.characterCanvas.keys where !characterIDs.contains(characterID) {
            issues.append(CoreText.format("人物坐标表包含不存在的人物 %@", String(describing: characterID)))
        }
        return issues
    }
}
