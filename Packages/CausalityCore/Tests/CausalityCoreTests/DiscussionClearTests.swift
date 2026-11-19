import Testing
@testable import CausalityCore

@Suite("讨论清空")
struct DiscussionClearTests {
    @Test("清空历史只删消息，保留讨论与引用")
    func clearMessagesKeepsDiscussion() throws {
        var project = StoryProject.empty(title: "清空讨论")
        let discussion = Discussion(title: "聊聊第二幕")
        try ProjectEditing.apply(ProjectMutations.appendDiscussion(discussion, to: project), to: &project)
        try ProjectEditing.apply(
            ProjectMutations.appendMessage(
                Message(role: .author, text: "先记一句"),
                to: discussion.id,
                in: project
            ),
            to: &project
        )
        #expect(project.discussions.first?.messages.count == 1)

        let operations = ProjectMutations.clearMessages(in: discussion.id, in: project)
        #expect(operations.count == 1)
        try ProjectEditing.apply(operations, to: &project)
        #expect(project.discussions.first?.messages.isEmpty == true)
        #expect(project.discussions.first?.title == "聊聊第二幕")
        #expect(project.discussions.first?.references == discussion.references)
    }
}
