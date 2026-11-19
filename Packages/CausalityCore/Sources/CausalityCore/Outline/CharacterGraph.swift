import Foundation

/// 思维导图里的人物。
public struct CharacterGraphNode: Identifiable, Sendable, Hashable {
    public var id: CharacterID
    public var character: StoryCharacter
    /// 出场场景。
    public var sceneIDs: [NodeID]
    /// 与其它人物之间的因果线条数。
    public var linkCount: Int
    /// 同一人物跨两条因果线的次数（他自己的推进）。
    public var selfAdvanceCount: Int

    public var sceneCount: Int { sceneIDs.count }
    public var hasAppeared: Bool { !sceneIDs.isEmpty }
}

/// 两个人之间的因果线，从一条故事发展线推导出来。
public struct CharacterGraphLink: Identifiable, Sendable, Hashable {
    public var id: String
    public var from: CharacterID
    public var to: CharacterID
    public var kind: EdgeKind
    /// 原发展线上的文字，例如「旧渡口只有梁婆婆替人捎过家书」。
    public var label: String
    public var fromTitle: String
    public var toTitle: String
    /// 这条因果是经由哪两条场景推出来的。
    public var viaTitles: String
    /// 归并了同样的几条线。
    public var weight: Int
}

/// 两个人同场出现的次数。人物图的主线按它画，权重就是共现场数。
public struct CharacterCoPresenceLink: Identifiable, Sendable, Hashable {
    public var id: String
    public var from: CharacterID
    public var to: CharacterID
    public var sceneIDs: [NodeID]
    public var sceneTitles: [String]
    public var weight: Int
}

/// 人物之间的亲属/亲友线，来自人物详情里选的称呼。
public struct CharacterKinLink: Identifiable, Sendable, Hashable {
    public var id: String
    public var from: CharacterID
    public var to: CharacterID
    public var kind: RelationKind
    public var isReverse: Bool
    /// 对方那侧写的关系。两边都写了才填，图上显示成「母亲/子女」。
    public var counterpartKind: RelationKind?

    public var label: String {
        guard let counterpartKind else { return kind.displayName }
        return "\(kind.displayName)/\(counterpartKind.displayName)"
    }
}

public struct CharacterGraph: Sendable {
    public var nodes: [CharacterGraphNode]
    /// 因果层：由故事发展线推出来，虚线画。
    public var links: [CharacterGraphLink]
    /// 同场共现：实线画，权重是共现场数。
    public var coPresenceLinks: [CharacterCoPresenceLink]
    public var kinships: [CharacterKinLink]

    public init(
        nodes: [CharacterGraphNode],
        links: [CharacterGraphLink],
        coPresenceLinks: [CharacterCoPresenceLink] = [],
        kinships: [CharacterKinLink] = []
    ) {
        self.nodes = nodes
        self.links = links
        self.coPresenceLinks = coPresenceLinks
        self.kinships = kinships
    }

    public static func build(project: StoryProject) -> CharacterGraph {
        let index = project.makeIndex()

        var scenesByCharacter: [CharacterID: [NodeID]] = [:]
        for character in project.characters {
            scenesByCharacter[character.id] = []
        }
        for node in project.nodes where node.status != .idea {
            for characterID in node.characterIDs where scenesByCharacter[characterID] != nil {
                scenesByCharacter[characterID, default: []].append(node.id)
            }
        }

        var mergedLinks: [String: CharacterGraphLink] = [:]
        var selfAdvances: [CharacterID: Int] = [:]

        for edge in project.edges {
            guard let fromNode = index.nodeByID[edge.from],
                  let toNode = index.nodeByID[edge.to],
                  fromNode.status != .idea,
                  toNode.status != .idea else { continue }

            let label = edge.label.isEmpty ? edge.kind.displayName : edge.label

            for fromCharacter in fromNode.characterIDs {
                for toCharacter in toNode.characterIDs {
                    if fromCharacter == toCharacter {
                        selfAdvances[fromCharacter, default: 0] += 1
                        continue
                    }
                    guard index.characterByID[fromCharacter] != nil,
                          index.characterByID[toCharacter] != nil else { continue }
                    let key = "\(fromCharacter.rawValue.uuidString)|\(toCharacter.rawValue.uuidString)|\(edge.kind.rawValue)|\(label)"
                    if var existing = mergedLinks[key] {
                        existing.weight += 1
                        mergedLinks[key] = existing
                    } else {
                        mergedLinks[key] = CharacterGraphLink(
                            id: key,
                            from: fromCharacter,
                            to: toCharacter,
                            kind: edge.kind,
                            label: label,
                            fromTitle: fromNode.title,
                            toTitle: toNode.title,
                            viaTitles: "\(fromNode.title) → \(toNode.title)",
                            weight: 1
                        )
                    }
                }
            }
        }

        var coPresence: [String: CharacterCoPresenceLink] = [:]
        for node in project.nodes where node.status != .idea {
            let ids = Array(Set(node.characterIDs))
                .filter { index.characterByID[$0] != nil }
                .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            guard ids.count >= 2 else { continue }
            for first in 0..<(ids.count - 1) {
                for second in (first + 1)..<ids.count {
                    let key = "\(ids[first].rawValue.uuidString)|\(ids[second].rawValue.uuidString)"
                    if var existing = coPresence[key] {
                        existing.sceneIDs.append(node.id)
                        existing.sceneTitles.append(node.title)
                        existing.weight += 1
                        coPresence[key] = existing
                    } else {
                        coPresence[key] = CharacterCoPresenceLink(
                            id: key,
                            from: ids[first],
                            to: ids[second],
                            sceneIDs: [node.id],
                            sceneTitles: [node.title],
                            weight: 1
                        )
                    }
                }
            }
        }
        let coPresenceLinks = coPresence.values.sorted {
            if $0.from.rawValue.uuidString != $1.from.rawValue.uuidString {
                return $0.from.rawValue.uuidString < $1.from.rawValue.uuidString
            }
            return $0.id < $1.id
        }

        let links = mergedLinks.values.sorted {
            if $0.from.rawValue.uuidString != $1.from.rawValue.uuidString {
                return $0.from.rawValue.uuidString < $1.from.rawValue.uuidString
            }
            return $0.id < $1.id
        }

        var linkCounts: [CharacterID: Int] = [:]
        for link in coPresenceLinks {
            linkCounts[link.from, default: 0] += 1
            linkCounts[link.to, default: 0] += 1
        }

        let nodes = project.characters.map { character in
            CharacterGraphNode(
                id: character.id,
                character: character,
                sceneIDs: scenesByCharacter[character.id] ?? [],
                linkCount: linkCounts[character.id] ?? 0,
                selfAdvanceCount: selfAdvances[character.id] ?? 0
            )
        }

        var kinships: [CharacterKinLink] = []
        // 一对人物只画一条亲属线：两边各自写「母亲」「子女」时不重复，也不叠字。
        var seenPairs: Set<String> = []
        for character in project.characters {
            for relation in character.relations {
                guard index.characterByID[relation.target] != nil, relation.target != character.id else { continue }
                let pairKey = [character.id.rawValue.uuidString, relation.target.rawValue.uuidString].sorted().joined(separator: "|")
                guard seenPairs.insert(pairKey).inserted else { continue }
                let counterpart = index.characterByID[relation.target]?.relations
                    .first { $0.target == character.id }?
                    .kind
                kinships.append(
                    CharacterKinLink(
                        id: "\(character.id.rawValue.uuidString)|\(relation.target.rawValue.uuidString)|\(relation.kind.rawValue)",
                        from: character.id,
                        to: relation.target,
                        kind: relation.kind,
                        isReverse: false,
                        counterpartKind: counterpart
                    )
                )
            }
        }

        return CharacterGraph(
            nodes: nodes,
            links: links,
            coPresenceLinks: coPresenceLinks,
            kinships: kinships
        )
    }
}
