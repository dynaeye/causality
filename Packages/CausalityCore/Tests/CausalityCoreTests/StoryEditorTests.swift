import Foundation
import Testing
@testable import CausalityCore

@Suite("编辑与撤销")
struct StoryEditorTests {
    @MainActor
    @Test("一组改动作为一笔撤销，再重做")
    func groupUndoRedo() throws {
        let script = ConvergenceDemo.make()
        let editor = StoryEditor(project: script.project)
        let original = editor.project

        let operations = ProjectMutations.updateNode(script.ending, in: editor.project) { $0.body = "新结局正文" }
        try editor.apply(operations, name: "修改结局")
        #expect(editor.project.node(script.ending)?.body == "新结局正文")
        #expect(editor.undoDepth == 1)
        #expect(editor.project.revision == original.revision + 1)

        #expect(try editor.undo())
        #expect(editor.project == original)
        #expect(editor.canRedo)

        #expect(try editor.redo())
        #expect(editor.project.node(script.ending)?.body == "新结局正文")
    }

    @MainActor
    @Test("连续输入合并成一笔撤销")
    func typingCoalesces() throws {
        let script = ConvergenceDemo.make()
        let editor = StoryEditor(project: script.project, coalescingWindow: 60)

        for suffix in ["一", "一二", "一二三"] {
            let operations = ProjectMutations.updateNode(script.ending, in: editor.project) { node in
                node.body = "结局正文" + suffix
            }
            try editor.apply(operations, name: "输入正文", coalescingKey: "node:\(script.ending):body")
        }

        #expect(editor.undoDepth == 1)
        #expect(try editor.undo())
        #expect(editor.project.node(script.ending)?.body.hasPrefix("旧渡口只剩半截石阶") == true)
    }

    @MainActor
    @Test("删除节点后，锁定的设定仍在，挂载关系被解除")
    func deletingNodeKeepsLockedSetting() throws {
        var script = ConvergenceDemo.make()
        var project = script.project
        let settingID = SettingID()
        let setting = Setting(
            id: settingID,
            title: "母亲离镇是因为欠信",
            text: "母亲当年替人捎信，欠了人情才离镇。",
            isConfirmed: true,
            isLocked: true,
            attachedNodeIDs: [script.ending]
        )
        try ProjectEditing.apply(ProjectMutations.appendSetting(setting, to: project), to: &project)
        try ProjectEditing.apply(ProjectMutations.attachSetting(settingID, to: script.ending, in: project), to: &project)
        script.project = project

        let editor = StoryEditor(project: project)
        try editor.apply(ProjectMutations.deleteNode(script.ending, in: project), name: "删除结局节点")

        #expect(editor.project.node(script.ending) == nil)
        let survived = editor.project.setting(settingID)
        #expect(survived != nil)
        #expect(survived?.isLocked == true)
        #expect(survived?.attachedNodeIDs.isEmpty == true)
        #expect(editor.project.edges.allSatisfy { $0.from != script.ending && $0.to != script.ending })
    }

    @MainActor
    @Test("撤销删除节点会恢复连线与挂载")
    func undoDeleteRestoresEverything() throws {
        var script = ConvergenceDemo.make()
        var project = script.project
        let settingID = SettingID()
        let setting = Setting(
            id: settingID,
            title: "河灯是梁婆婆扎的",
            isConfirmed: true,
            isLocked: false,
            attachedNodeIDs: [script.grandaunt]
        )
        try ProjectEditing.apply(ProjectMutations.appendSetting(setting, to: project), to: &project)
        script.project = project

        let editor = StoryEditor(project: project)
        try editor.apply(ProjectMutations.deleteNode(script.grandaunt, in: project), name: "删除梁婆婆场景")
        #expect(editor.project.edges.count == project.edges.count - 3)

        #expect(try editor.undo())
        #expect(editor.project == project)
    }

    @Test("锁定设定不允许删除")
    func lockedSettingCannotBeDeleted() throws {
        var project = StoryProject.empty(title: "锁定")
        let setting = Setting(title: "已锁", isConfirmed: true, isLocked: true)
        try ProjectEditing.apply(ProjectMutations.appendSetting(setting, to: project), to: &project)

        var caught: EditError?
        do {
            let operations = try ProjectMutations.deleteSetting(setting.id, in: project)
            try ProjectEditing.apply(operations, to: &project)
        } catch let error as EditError {
            caught = error
        }
        #expect(caught == .lockedSetting(setting.id))
        #expect(project.settings.count == 1)
    }

    @Test("锁定自动带上确认")
    func lockingImpliesConfirmed() throws {
        var project = StoryProject.empty(title: "锁定")
        let setting = Setting(title: "待锁")
        try ProjectEditing.apply(ProjectMutations.appendSetting(setting, to: project), to: &project)
        try ProjectEditing.apply(ProjectMutations.setSettingLocked(setting.id, true, in: project), to: &project)
        #expect(project.setting(setting.id)?.isConfirmed == true)
        #expect(project.setting(setting.id)?.isLocked == true)

        try ProjectEditing.apply(ProjectMutations.setSettingConfirmed(setting.id, false, in: project), to: &project)
        #expect(project.setting(setting.id)?.isLocked == false)
    }

    @Test("失败的操作不会留下半截改动")
    func failedOperationsRollBack() throws {
        var script = ConvergenceDemo.make()
        var project = script.project
        let before = project
        let bogus = EditOperation.deleteNode(
            StoryNode(id: NodeID(), title: "不存在的"),
            index: 0
        )
        var caught: EditError?
        do {
            try ProjectEditing.apply([.setCanvasPoint(script.lantern, before: nil, after: .zero), bogus], to: &project)
        } catch let error as EditError {
            caught = error
        }
        #expect(caught != nil)
        #expect(project == before)
        script.project = project
    }
}
