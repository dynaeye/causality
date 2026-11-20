import CausalityCore
import SwiftUI

extension ProjectSession {
    func requestSave() {
        Task { await save() }
    }

    func textBinding(_ id: NodeID, _ keyPath: WritableKeyPath<StoryNode, String>, field: String) -> Binding<String> {
        Binding(
            get: { self.project?.node(id)?[keyPath: keyPath] ?? "" },
            set: { newValue in
                self.updateNode(id, coalescingKey: "node:\(id):\(field)") { node in
                    node[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func intBinding(_ id: NodeID, _ keyPath: WritableKeyPath<StoryNode, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.project?.node(id)?[keyPath: keyPath] ?? false },
            set: { newValue in
                self.updateNode(id) { node in node[keyPath: keyPath] = newValue }
            }
        )
    }

    func kindBinding(_ id: NodeID) -> Binding<NodeKind> {
        Binding(
            get: { self.project?.node(id)?.kind ?? .event },
            set: { newValue in self.updateNode(id) { node in node.kind = newValue } }
        )
    }

    func chapterBinding(_ id: NodeID) -> Binding<ChapterID?> {
        Binding(
            get: { self.project?.node(id)?.chapterID },
            set: { newValue in
                guard let project = self.project else { return }
                self.apply(ProjectMutations.moveNode(id, toChapter: newValue, at: nil, in: project), name: InterfaceLanguage.label("移动章节"))
            }
        )
    }
}

// MARK: - 小组件

struct KindBadge: View {
    @Environment(\.theme) private var theme
    let kind: NodeKind

    var body: some View {
        Text(LocalizedStringKey(kind.displayName))
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        theme.kindColor(for: kind)
    }
}

/// 缩略图。按需解码，画布与详情都用它。
struct CoverThumbnail: View {
    @Environment(\.theme) private var theme
    let asset: Asset
    let packageURL: URL?
    var maxPixel: Int = 320
    var cornerRadius: CGFloat = 6

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                // Color.clear 只占容器给的尺寸，图片作为 overlay 撑大后再裁掉，
                // 这样 scaledToFill 不会把外层布局撑宽、压到别的控件上。
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
            } else {
                Rectangle()
                    .fill(theme.imageWell)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(theme.textTertiary)
                    }
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: "\(asset.id)-\(maxPixel)") {
            await load()
        }
    }

    private func load() async {
        guard let packageURL else { return }
        if let data = await ThumbnailService.shared.jpegData(
            packageURL: packageURL,
            asset: asset,
            maxPixel: maxPixel
        ) {
            image = NSImage(data: data)
        }
    }
}

struct SearchResultsList: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    let results: [(node: StoryNode, chapterTitle: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: InterfaceLanguage.label("搜索结果 %lld"), results.count))
                .font(theme.fontMin)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            ForEach(results, id: \.node.id) { result in
                Button {
                    jump(to: result.node)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(highlighted(result.node.title))
                            .font(theme.fontBody)
                        Text(highlighted(subtitle(for: result)))
                            .font(theme.fontMin)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        session.selectedNodeID == result.node.id
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 第二行：标题里有命中原样给章名与梗概；命中在梗概或正文里，就裁一段把它放在看得见的位置。
    private func subtitle(for result: (node: StoryNode, chapterTitle: String)) -> String {
        let node = result.node
        let head = result.chapterTitle + " · "
        let query = session.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return head + node.summary }
        if node.title.localizedCaseInsensitiveContains(query) {
            return head + node.summary
        }
        let source = node.summary.localizedCaseInsensitiveContains(query) ? node.summary : node.body
        guard let range = source.range(of: query, options: [.caseInsensitive]) else {
            return head + node.summary
        }
        let start = source.index(range.lowerBound, offsetBy: -6, limitedBy: source.startIndex) ?? source.startIndex
        let end = source.index(range.upperBound, offsetBy: 46, limitedBy: source.endIndex) ?? source.endIndex
        let core = source[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > source.startIndex ? "…" : "") + core + (end < source.endIndex ? "…" : "")
    }

    /// 命中处上底色。查询词按大小写不敏感、连字不敏感匹配。
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let query = session.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return attributed }

        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex) {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].backgroundColor = theme.accent.opacity(0.32)
                attributed[lower..<upper].foregroundColor = theme.textPrimary
            }
            start = range.upperBound
        }
        return attributed
    }

    /// 跳到那张卡：有章节的进大纲并滚到它，灵感卡回故事板。
    private func jump(to node: StoryNode) {
        session.selectedNodeID = node.id
        if let chapterID = node.chapterID {
            session.focusedChapterID = chapterID
            session.viewMode = .outline
        } else {
            session.viewMode = .storyboard
        }
    }
}

// MARK: - 可达结局

/// 右键菜单里的一项：从这张卡往后能到哪些结局、各要几步。
struct ReachableEndingsMenu: View {
    @Bindable var session: ProjectSession
    let nodeID: NodeID

    var body: some View {
        let endings = session.project.map { EndingReach.from(nodeID, in: $0) } ?? []
        Menu("之后可达的结局") {
            if endings.isEmpty {
                Button("之后没有结局") {}
                    .disabled(true)
            } else {
                ForEach(endings) { ending in
                    let mainlineSuffix = ending.onMainline ? InterfaceLanguage.label(" · 主线") : ""
                    Button(String(format: InterfaceLanguage.label("%@ · %lld 步%@"), ending.title, ending.steps, mainlineSuffix)) {
                        session.selectedNodeID = ending.endingID
                        session.focusedChapterID = session.project?.node(ending.endingID)?.chapterID
                    }
                }
            }
        }
    }
}

// MARK: - 字数文案

/// 界面上的字数写法。四级共用一处，避免「1.2 万」与「12000」混着出现。
/// 一万以内给千分位（1,234 字），过万换成万字（12.4 万字）。
enum WordCountText {
    static func text(_ count: Int) -> String {
        guard count >= 10_000, InterfaceLanguage.current.identifier != "en" else {
            return String(format: InterfaceLanguage.label("%@ 字"), number(count))
        }
        return String(format: InterfaceLanguage.label("%@%@字"), wan(count), tenThousand)
    }

    /// 只给数字（过万带「万」），用在「字数 12.4 万」这类已经点了单位的写法里。
    static func bare(_ count: Int) -> String {
        guard count >= 10_000, InterfaceLanguage.current.identifier != "en" else {
            return number(count)
        }
        return "\(wan(count))\(tenThousand)"
    }

    /// 繁体中文用「萬」，日文与简体用「万」。
    private static var tenThousand: String {
        InterfaceLanguage.label("万")
    }

    private static func number(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }

    private static func wan(_ count: Int) -> String {
        let value = Double(count) / 10_000
        var text = String(format: value >= 100 ? "%.0f" : "%.1f", value)
        if text.hasSuffix(".0") {
            text.removeLast(2)
        }
        return text
    }
}

// MARK: - 简单流式布局

struct FlowRow: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > width, cursorX > 0 {
                cursorX = 0
                cursorY += rowHeight + spacing
                rowHeight = 0
            }
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: cursorY + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > bounds.maxX, cursorX > bounds.minX {
                cursorX = bounds.minX
                cursorY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: cursorX, y: cursorY), proposal: ProposedViewSize(size))
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 画布右下角的一行提示：滚轮语义改过，头一周给个说明，过期自动消失。
struct CanvasScrollHint: View {
    @Environment(\.theme) private var theme
    @AppStorage("causal.wheelHintDeadline") private var deadline: Double = 0

    var body: some View {
        Group {
            if Date().timeIntervalSince1970 < deadline {
                Text("滚轮平移 · ⌘滚轮缩放")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.surface.opacity(0.9), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(theme.border, lineWidth: 1)
                    }
            }
        }
        .onAppear {
            if deadline == 0 {
                deadline = Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970
            }
        }
    }
}
