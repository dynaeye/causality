import CausalityCore
import SwiftUI

extension InspectorPane {
    func threadsSection(_ node: StoryNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.threads.isEmpty {
                Text("还没有线索。打开「线索」面板（⇧⌘L）新建一条。")
                    .font(theme.fontMin)
                    .foregroundStyle(theme.textTertiary)
            }
            ForEach(session.threads) { thread in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(threadColor(thread.kind))
                            .frame(width: 6, height: 6)
                        Text(thread.name)
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Menu("把本场记为…") {
                            ForEach(ThreadRole.allCases, id: \.self) { role in
                                Button(LocalizedStringKey(role.displayName)) {
                                    session.addThreadEntry(thread.id, nodeID: node.id, role: role)
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .font(theme.fontMin)
                    }

                    ForEach(session.entries(of: thread, at: node.id)) { entry in
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(entry.role.displayName))
                                .font(.system(size: 10))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(threadColor(thread.kind).opacity(0.16), in: Capsule())
                                .foregroundStyle(threadColor(thread.kind))
                            TextField("这一笔写什么", text: entryTextBinding(thread: thread, entry: entry))
                                .textFieldStyle(.roundedBorder)
                                .font(theme.fontMin)
                            Button {
                                session.removeThreadEntry(thread.id, entryID: entry.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    func threadHint(_ node: StoryNode) -> String {
        let names = session.threads(at: node.id).map(\.name)
        return names.isEmpty ? "未挂线索" : names.joined(separator: "、")
    }

    private func entryTextBinding(thread: StoryThread, entry: ThreadEntry) -> Binding<String> {
        Binding(
            get: {
                session.project?.threads
                    .first { $0.id == thread.id }?
                    .entries.first { $0.id == entry.id }?
                    .text ?? ""
            },
            set: { value in
                session.updateThreadEntryText(thread.id, entryID: entry.id, text: value)
            }
        )
    }

    private func threadColor(_ kind: ThreadKind) -> Color {
        switch kind {
        case .foreshadow: theme.accent
        case .theme: theme.choice
        case .arc: theme.ending
        case .quest: theme.warning
        case .reveal: .purple
        }
    }
}
