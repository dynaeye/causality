import AppKit
import Foundation
import CausalityCore
import UniformTypeIdentifiers

// MARK: - 试玩

extension ProjectSession {
    func startPlaythrough() {
        guard let project, let play = PlaythroughEngine.start(in: project) else { return }
        isWriting = false
        isAuditing = false
        isSynopsizing = false
        isThreading = false
        isPlaying = true
        playthrough = play
    }

    func restartPlaythrough() {
        startPlaythrough()
    }

    func closePlaythrough() {
        isPlaying = false
        playthrough = nil
    }

    func choosePlaythrough(_ edgeID: EdgeID) {
        guard let project, let play = playthrough,
              let next = PlaythroughEngine.choose(edgeID, in: play, project: project) else { return }
        playthrough = next
    }

    func backPlaythrough() {
        guard let project, let play = playthrough,
              let previous = PlaythroughEngine.back(play, project: project) else { return }
        playthrough = previous
    }

    func jumpPlaythrough(to index: Int) {
        guard let project, let play = playthrough,
              let jumped = PlaythroughEngine.jump(to: index, in: play, project: project) else { return }
        playthrough = jumped
    }

    func exportPlaythrough() {
        guard let project, let play = playthrough else { return }
        let language = workLanguage
        let markdown = PlaythroughMarkdown.render(play, project: project, localize: language.label)
        let name = "\(project.title)-\(language.label("试读稿")).md"
        Task {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = name
            guard let url = await FilePanels.url(panel) else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
