import Foundation

/// 故事板上的并列组：一个分叉点，连同它到汇合点之间的一串卡。
///
/// 只按 `chapter.order` 与出边算；一个分叉的所有同章目标进入同一组，
/// 成员按章内顺序排列，组在「所有分支共同可达的第一张卡」处闭合。
public struct AlternateGroup: Identifiable, Sendable, Equatable {
    public var forkNodeID: NodeID
    public var branchNodeIDs: [NodeID]
    public var memberNodeIDs: [NodeID]
    public var closeNodeID: NodeID?
    /// 每张成员卡属于第几条分支；分叉点自己不在表里。
    public var branchByNode: [NodeID: Int]

    public var id: String { forkNodeID.rawValue.uuidString }
    public var branchCount: Int { branchNodeIDs.count }
}

public enum AlternateGroups {
    /// 一章里的所有并列组。当前只处理一层：组内再分叉不另开组。
    public static func compute(chapter: Chapter, project: StoryProject) -> [AlternateGroup] {
        let index = project.makeIndex()
        var ordered: [NodeID] = []
        var seen: Set<NodeID> = []
        for id in chapter.order {
            guard let node = index.nodeByID[id],
                  node.status == .draft,
                  node.chapterID == chapter.id,
                  seen.insert(id).inserted else { continue }
            ordered.append(id)
        }

        func reachable(from start: NodeID) -> Set<NodeID> {
            var seen: Set<NodeID> = []
            var stack = [start]
            while let id = stack.popLast() {
                guard seen.insert(id).inserted else { continue }
                for edge in index.outgoingEdges(of: id) {
                    guard let target = index.nodeByID[edge.to],
                          target.status == .draft,
                          target.chapterID == chapter.id else { continue }
                    stack.append(edge.to)
                }
            }
            return seen
        }

        var groups: [AlternateGroup] = []
        var position = 0
        while position < ordered.count {
            let nodeID = ordered[position]
            if project.cardGroupOverrides[nodeID.rawValue.uuidString] != nil {
                position += 1
                continue
            }
            let targets = orderedUnique(
                index.outgoingEdges(of: nodeID)
                    .map(\.to)
                    .filter { target in
                        guard let node = index.nodeByID[target] else { return false }
                        return node.status == .draft && node.chapterID == chapter.id
                    }
            )
            guard targets.count >= 2 else {
                position += 1
                continue
            }

            let reachSets = targets.map { reachable(from: $0) }
            var closeIndex: Int?
            if !reachSets.isEmpty {
                for candidate in (position + 1)..<ordered.count {
                    if reachSets.allSatisfy({ $0.contains(ordered[candidate]) }) {
                        closeIndex = candidate
                        break
                    }
                }
            }
            let end = closeIndex ?? ordered.count
            guard end > position + 1 else {
                position += 1
                continue
            }
            let members = Array(ordered[(position + 1)..<end])
            var branchByNode: [NodeID: Int] = [:]
            for (branch, target) in targets.enumerated() {
                for member in members where reachSets[branch].contains(member) {
                    if branchByNode[member] == nil {
                        branchByNode[member] = branch
                    }
                }
                branchByNode[target] = branch
            }
            groups.append(
                AlternateGroup(
                    forkNodeID: nodeID,
                    branchNodeIDs: targets,
                    memberNodeIDs: members,
                    closeNodeID: closeIndex.map { ordered[$0] },
                    branchByNode: branchByNode
                )
            )
            position = end
        }
        return groups
    }

    private static func orderedUnique(_ ids: [NodeID]) -> [NodeID] {
        var seen: Set<NodeID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
