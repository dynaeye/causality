import CausalityCore
import SwiftUI

/// 长文本编辑器。
///
/// 直接绑模型的 `TextEditor` 会在拼音组字期间逐键提交；这里只把文本写进会话草稿，
/// 停输 400 ms、失焦、切换场景或人物时各提交一次。
struct TextDraftEditor: View {
    @Bindable var session: ProjectSession
    let field: TextDraftField
    var autoFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: session.textDraftBinding(field))
            .focused($focused)
            .onAppear {
                if autoFocus {
                    focused = true
                }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    session.commitTextDraft(field)
                }
            }
            .onChange(of: field) { oldField, _ in
                session.commitTextDraft(oldField)
            }
            .onDisappear {
                session.commitTextDraft(field)
            }
    }
}
