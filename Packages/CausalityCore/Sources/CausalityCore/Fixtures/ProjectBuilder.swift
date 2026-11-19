import Foundation

/// SplitMix64：固定种子下可完全复现的随机数发生器。
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        Double(next() % 1_000_000) / 1_000_000.0 < probability
    }
}

/// 由固定种子生成稳定 UUID，使 fixture 每次生成的工程字节一致。
public struct SeededIDGenerator {
    private var random: SplitMix64

    public init(seed: UInt64) {
        self.random = SplitMix64(seed: seed)
    }

    public mutating func next<Tag>() -> ID<Tag> {
        var hex = ""
        for _ in 0 ..< 16 {
            hex += String(format: "%02x", UInt8(truncatingIfNeeded: random.next()))
        }
        let part1 = hex.prefix(8)
        let part2 = hex.dropFirst(8).prefix(4)
        let part3 = hex.dropFirst(13).prefix(3)
        let part4 = hex.dropFirst(17).prefix(3)
        let part5 = hex.dropFirst(20).prefix(12)
        let formatted = "\(part1)-\(part2)-4\(part3)-a\(part4)-\(part5)"
        guard let uuid = UUID(uuidString: formatted) else {
            return ID<Tag>()
        }
        return ID<Tag>(rawValue: uuid)
    }
}

/// 固定时钟。fixture 的时间戳不随运行时刻变化。
public struct FixtureClock {
    private var current: Date

    public init(start: Date = Date(timeIntervalSince1970: 1_767_225_600)) {
        self.current = start
    }

    public mutating func now() -> Date {
        defer { current = current.addingTimeInterval(60) }
        return current
    }
}

/// 构造 fixture 与测试项目用的小工具。所有改动都走 `ProjectMutations`。
public struct ProjectBuilder {
    public private(set) var project: StoryProject
    private var ids: SeededIDGenerator
    private var clock: FixtureClock

    public init(
        seed: UInt64,
        title: String,
        logline: String = "",
        chapterTitle: String = CoreText.text("第一章")
    ) {
        var ids = SeededIDGenerator(seed: seed)
        let chapterID: ChapterID = ids.next()
        var clock = FixtureClock()
        let now = clock.now()
        let chapter = Chapter(id: chapterID, title: chapterTitle, createdAt: now)
        self.ids = ids
        self.clock = clock
        self.project = StoryProject(
            id: UUID(uuidString: "00000000-0000-4000-a000-000000000000") ?? UUID(),
            title: title,
            logline: logline,
            createdAt: now,
            modifiedAt: now,
            chapters: [chapter]
        )
    }

    public init(project: StoryProject, seed: UInt64 = 1) {
        self.project = project
        self.ids = SeededIDGenerator(seed: seed)
        self.clock = FixtureClock()
    }

    public mutating func apply(_ operations: [EditOperation]) {
        try? ProjectEditing.apply(operations, to: &project)
    }

    public mutating func addChapter(title: String, summary: String = "") -> ChapterID {
        let chapter = Chapter(id: ids.next(), title: title, summary: summary, createdAt: clock.now())
        apply(ProjectMutations.appendChapter(chapter, to: project))
        return chapter.id
    }

    public mutating func addNode(
        title: String,
        kind: NodeKind = .event,
        summary: String = "",
        body: String = "",
        chapterID: ChapterID? = nil,
        isEntry: Bool = false,
        status: NodeStatus = .draft,
        characters: [CharacterID] = [],
        places: [PlaceID] = [],
        settings: [SettingID] = [],
        position: CanvasPoint? = nil
    ) -> NodeID {
        let now = clock.now()
        let node = StoryNode(
            id: ids.next(),
            kind: kind,
            status: status,
            title: title,
            summary: summary,
            body: body,
            chapterID: chapterID,
            isEntry: isEntry,
            characterIDs: characters,
            placeIDs: places,
            settingIDs: settings,
            createdAt: now,
            modifiedAt: now
        )
        apply(ProjectMutations.appendNode(node, to: project))
        if let position {
            apply(ProjectMutations.setCanvasPoint(position, for: node.id, in: project))
        }
        return node.id
    }

    public mutating func addCharacter(name: String, summary: String = "") -> CharacterID {
        let character = StoryCharacter(id: ids.next(), name: name, summary: summary)
        apply(ProjectMutations.appendCharacter(character, to: project))
        return character.id
    }

    public mutating func addPlace(name: String, summary: String = "") -> PlaceID {
        let place = StoryPlace(id: ids.next(), name: name, summary: summary)
        apply(ProjectMutations.appendPlace(place, to: project))
        return place.id
    }

    public mutating func addSetting(
        title: String,
        text: String = "",
        confirmed: Bool = false,
        locked: Bool = false,
        attachedTo nodeID: NodeID? = nil
    ) -> SettingID {
        let now = clock.now()
        var setting = Setting(
            id: ids.next(),
            title: title,
            text: text,
            isConfirmed: confirmed,
            isLocked: locked,
            attachedNodeIDs: nodeID.map { [$0] } ?? [],
            createdAt: now,
            modifiedAt: now
        )
        setting.normalize()
        apply(ProjectMutations.appendSetting(setting, to: project))
        return setting.id
    }

    @discardableResult
    public mutating func connect(
        _ from: NodeID,
        to: NodeID,
        kind: EdgeKind = .plain,
        label: String = "",
        condition: String = ""
    ) -> EdgeID {
        let edge = StoryEdge(
            id: ids.next(),
            from: from,
            to: to,
            kind: kind,
            label: label,
            condition: condition
        )
        apply([.insertEdge(edge, index: project.edges.count)])
        return edge.id
    }

    public mutating func setHeader(title: String? = nil, logline: String? = nil) {
        apply(ProjectMutations.updateHeader(title: title, logline: logline, in: project))
    }

    public mutating func setPosition(_ point: CanvasPoint, for nodeID: NodeID) {
        apply(ProjectMutations.setCanvasPoint(point, for: nodeID, in: project))
    }

    public mutating func attach(_ settingID: SettingID, to nodeID: NodeID) {
        apply(ProjectMutations.attachSetting(settingID, to: nodeID, in: project))
    }

    public func finalized() -> StoryProject {
        project
    }
}
