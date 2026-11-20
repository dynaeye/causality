import Foundation

/// 故事结构（节点、发展线、章节）的落地实现。与 `EditOperation` 的声明分开，便于逐个验收。
extension EditOperation {
    func applyNodeChange(to project: inout StoryProject) throws {
        switch self {
        case let .insertNode(node, index):
            guard !project.nodes.contains(where: { $0.id == node.id }) else {
                throw EditError.duplicateID(CoreText.format("节点 %@", String(describing: node.id)))
            }
            project.nodes.insert(node, at: clamped(index, project.nodes.count))

        case let .deleteNode(node, _):
            guard let position = project.nodes.firstIndex(where: { $0.id == node.id }) else {
                throw EditError.nodeNotFound(node.id)
            }
            project.nodes.remove(at: position)
            project.canvas[node.id] = nil
            // 引用这张卡的派生状态一起清掉，别留悬空指针。
            if project.workingRouteEndingID == node.id {
                project.workingRouteEndingID = nil
            }
            project.cardGroupOverrides[node.id.rawValue.uuidString] = nil

        case let .replaceNode(before, after):
            guard let position = project.nodes.firstIndex(where: { $0.id == before.id }) else {
                throw EditError.nodeNotFound(before.id)
            }
            project.nodes[position] = after

        default:
            throw EditError.invalidOperation(CoreText.format("节点操作收到 %@", String(describing: self)))
        }
    }

    func applyEdgeChange(to project: inout StoryProject) throws {
        switch self {
        case let .insertEdge(edge, index):
            guard !project.edges.contains(where: { $0.id == edge.id }) else {
                throw EditError.duplicateID(CoreText.format("发展线 %@", String(describing: edge.id)))
            }
            project.edges.insert(edge, at: clamped(index, project.edges.count))

        case let .deleteEdge(edge, _):
            guard let position = project.edges.firstIndex(where: { $0.id == edge.id }) else {
                throw EditError.edgeNotFound(edge.id)
            }
            project.edges.remove(at: position)

        case let .replaceEdge(before, after):
            guard let position = project.edges.firstIndex(where: { $0.id == before.id }) else {
                throw EditError.edgeNotFound(before.id)
            }
            project.edges[position] = after

        default:
            throw EditError.invalidOperation(CoreText.format("发展线操作收到 %@", String(describing: self)))
        }
    }

    func applyChapterChange(to project: inout StoryProject) throws {
        switch self {
        case let .insertChapter(chapter, index):
            guard !project.chapters.contains(where: { $0.id == chapter.id }) else {
                throw EditError.duplicateID(CoreText.format("章节 %@", String(describing: chapter.id)))
            }
            project.chapters.insert(chapter, at: clamped(index, project.chapters.count))

        case let .deleteChapter(chapter, _):
            guard let position = project.chapters.firstIndex(where: { $0.id == chapter.id }) else {
                throw EditError.chapterNotFound(chapter.id)
            }
            project.chapters.remove(at: position)

        case let .replaceChapter(before, after):
            guard let position = project.chapters.firstIndex(where: { $0.id == before.id }) else {
                throw EditError.chapterNotFound(before.id)
            }
            project.chapters[position] = after

        default:
            throw EditError.invalidOperation(CoreText.format("章节操作收到 %@", String(describing: self)))
        }
    }

    func applyCharacterChange(to project: inout StoryProject) throws {
        switch self {
        case let .insertCharacter(value, index):
            guard !project.characters.contains(where: { $0.id == value.id }) else {
                throw EditError.duplicateID(CoreText.format("人物 %@", String(describing: value.id)))
            }
            project.characters.insert(value, at: clamped(index, project.characters.count))

        case let .deleteCharacter(value, _):
            guard let position = project.characters.firstIndex(where: { $0.id == value.id }) else {
                throw EditError.characterNotFound(value.id)
            }
            project.characters.remove(at: position)
            project.characterCanvas[value.id] = nil
            for nodeIndex in project.nodes.indices {
                project.nodes[nodeIndex].characterIDs.removeAll { $0 == value.id }
            }
            for characterIndex in project.characters.indices {
                project.characters[characterIndex].relations.removeAll { $0.target == value.id }
            }

        case let .replaceCharacter(before, after):
            guard let position = project.characters.firstIndex(where: { $0.id == before.id }) else {
                throw EditError.characterNotFound(before.id)
            }
            project.characters[position] = after

        default:
            throw EditError.invalidOperation(CoreText.format("人物操作收到 %@", String(describing: self)))
        }
    }

    func applyPlaceChange(to project: inout StoryProject) throws {
        switch self {
        case let .insertPlace(value, index):
            guard !project.places.contains(where: { $0.id == value.id }) else {
                throw EditError.duplicateID(CoreText.format("地点 %@", String(describing: value.id)))
            }
            project.places.insert(value, at: clamped(index, project.places.count))

        case let .deletePlace(value, _):
            guard let position = project.places.firstIndex(where: { $0.id == value.id }) else {
                throw EditError.placeNotFound(value.id)
            }
            project.places.remove(at: position)
            for nodeIndex in project.nodes.indices {
                project.nodes[nodeIndex].placeIDs.removeAll { $0 == value.id }
            }

        case let .replacePlace(before, after):
            guard let position = project.places.firstIndex(where: { $0.id == before.id }) else {
                throw EditError.placeNotFound(before.id)
            }
            project.places[position] = after

        default:
            throw EditError.invalidOperation(CoreText.format("地点操作收到 %@", String(describing: self)))
        }
    }
}

func clamped(_ value: Int, _ upperBound: Int) -> Int {
    min(max(value, 0), upperBound)
}
