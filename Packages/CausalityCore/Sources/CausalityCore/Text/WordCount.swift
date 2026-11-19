import Foundation

/// 字数统计。中文按字、英文按词，空白与标点不计。
///
/// 口径写死在一处：场景、章、路线、全书四级都调它，导出与界面才说得上同一句话。
public enum WordCount {
    /// 一段正文的字数。
    public static func count(_ text: String) -> Int {
        var total = 0
        var inLatinWord = false

        for character in text {
            if character.isWhitespace {
                inLatinWord = false
                continue
            }
            if character.isPunctuation {
                inLatinWord = false
                continue
            }
            if isCJK(character) {
                total += 1
                inLatinWord = false
                continue
            }
            if character.isLetter || character.isNumber {
                if !inLatinWord {
                    total += 1
                    inLatinWord = true
                }
                continue
            }
            // 表情与其他符号各算一个。
            total += 1
            inLatinWord = false
        }
        return total
    }

    /// 一场戏的字数（只算正文）。
    public static func count(of node: StoryNode) -> Int {
        count(node.body)
    }

    /// 一章的字数。
    public static func count(of chapterID: ChapterID, in project: StoryProject) -> Int {
        project.nodes
            .filter { $0.chapterID == chapterID && $0.status == .draft }
            .reduce(0) { $0 + count($1.body) }
    }

    /// 一条路上的字数（只算正式场景，与章、全书同口径）。
    public static func count(of route: StoryRoute, in project: StoryProject) -> Int {
        project.nodes
            .filter { $0.status == .draft && route.nodeIDs.contains($0.id) }
            .reduce(0) { $0 + count($1.body) }
    }

    /// 全书字数（正式场景）。
    public static func total(in project: StoryProject) -> Int {
        project.nodes
            .filter { $0.status == .draft }
            .reduce(0) { $0 + count($1.body) }
    }

    /// 一次遍历算好的字数表。界面每次刷新只建一份，四级读数都从这里取。
    ///
    /// 逐卡正文各算一遍；章、路线、全书只把正式场景加总，灵感卡不计入。
    public struct Book: Sendable, Equatable {
        /// 每张卡的正文长度（含灵感卡）。
        public let byNode: [NodeID: Int]
        /// 每章的正文长度（只算正式场景）。
        public let byChapter: [ChapterID: Int]
        /// 全书正文长度（只算正式场景）。
        public let total: Int
        /// 正式场景数。
        public let sceneCount: Int
        /// 写作状态为「定稿」的正式场景数。
        public let finalCount: Int
        private let draftNodeIDs: Set<NodeID>

        public static let empty = Book(
            byNode: [:],
            byChapter: [:],
            total: 0,
            sceneCount: 0,
            finalCount: 0,
            draftNodeIDs: []
        )

        private init(
            byNode: [NodeID: Int],
            byChapter: [ChapterID: Int],
            total: Int,
            sceneCount: Int,
            finalCount: Int,
            draftNodeIDs: Set<NodeID>
        ) {
            self.byNode = byNode
            self.byChapter = byChapter
            self.total = total
            self.sceneCount = sceneCount
            self.finalCount = finalCount
            self.draftNodeIDs = draftNodeIDs
        }

        public init(project: StoryProject) {
            var byNode: [NodeID: Int] = [:]
            var byChapter: [ChapterID: Int] = [:]
            var draftNodeIDs: Set<NodeID> = []
            var total = 0
            var finalCount = 0
            byNode.reserveCapacity(project.nodes.count)
            draftNodeIDs.reserveCapacity(project.nodes.count)
            for node in project.nodes {
                let words = WordCount.count(node.body)
                byNode[node.id] = words
                guard node.status == .draft else { continue }
                draftNodeIDs.insert(node.id)
                total += words
                if let chapterID = node.chapterID {
                    byChapter[chapterID, default: 0] += words
                }
                if node.writingState == .final {
                    finalCount += 1
                }
            }
            self.byNode = byNode
            self.byChapter = byChapter
            self.total = total
            self.sceneCount = draftNodeIDs.count
            self.finalCount = finalCount
            self.draftNodeIDs = draftNodeIDs
        }

        /// 一张卡的字数。灵感卡也有正文，所以这里不过滤状态。
        public func count(of nodeID: NodeID) -> Int {
            byNode[nodeID] ?? 0
        }

        /// 一章的字数（只算正式场景）。
        public func count(of chapterID: ChapterID) -> Int {
            byChapter[chapterID] ?? 0
        }

        /// 一条路上的字数（只算正式场景）。
        public func count(of route: StoryRoute) -> Int {
            var words = 0
            for nodeID in route.nodeIDs where draftNodeIDs.contains(nodeID) {
                words += byNode[nodeID] ?? 0
            }
            return words
        }
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF,     // 假名
             0x3400...0x4DBF,     // 扩展 A
             0x4E00...0x9FFF,     // 基本汉字
             0xF900...0xFAFF,     // 兼容汉字
             0xAC00...0xD7AF,     // 谚文
             0x20000...0x2FA1F:   // 扩展 B 及以后
            return true
        default:
            return false
        }
    }
}
