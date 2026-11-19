import CausalityCore
import SwiftUI

/// 人物 × 章节矩阵。行按首次出场排序，点格跳到大纲。
struct CharacterMatrixView: View {
    @Environment(\.theme) private var theme
    @Bindable var session: ProjectSession
    let matrix: CharacterMatrix

    private let nameWidth: CGFloat = 150
    private let cellWidth: CGFloat = 86
    private let tailWidth: CGFloat = 190

    var body: some View {
        VStack(spacing: 0) {
            legend
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    ForEach(matrix.rows) { row in
                        rowView(row)
                        Rectangle().fill(theme.border.opacity(0.5)).frame(height: 1)
                    }
                    if matrix.rows.isEmpty {
                        Text("还没有人物。先在场景详情里加人物。")
                            .font(theme.fontMin)
                            .foregroundStyle(theme.textTertiary)
                            .padding(16)
                    }
                }
                .padding(14)
            }
        }
        .background(theme.background)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.present, color: theme.accent)
            legendItem(.mentioned, color: theme.warning)
            legendItem(.absent, color: theme.borderStrong)
            legendItem(.unwritten, color: theme.border)
            Spacer()
            Text("\(matrix.rows.count) 人 × \(matrix.chapters.count) 章")
                .font(theme.fontMin)
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    private func legendItem(_ presence: MatrixPresence, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(presence == .present ? 0.85 : 0.35))
                .frame(width: 10, height: 10)
            Text(LocalizedStringKey(presence.displayName))
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("人物")
                .font(theme.fontMinBold)
                .foregroundStyle(theme.textSecondary)
                .frame(width: nameWidth, alignment: .leading)
            ForEach(Array(matrix.chapters.enumerated()), id: \.element.id) { index, chapter in
                VStack(spacing: 1) {
                    Text(chapter.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Text(WordCountText.text(matrix.chapterWordCounts[index]))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(width: cellWidth)
            }
            Text("首 / 末 / 空档")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .frame(width: tailWidth, alignment: .leading)
                .padding(.leading, 10)
        }
        .padding(.vertical, 6)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    private func rowView(_ row: CharacterMatrixRow) -> some View {
        HStack(spacing: 0) {
            Button {
                session.focusedCharacterID = session.focusedCharacterID == row.id ? nil : row.id
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.firstChapterIndex == nil ? theme.borderStrong : theme.accent)
                        .frame(width: 6, height: 6)
                    Text(verbatim: row.character.name.isEmpty ? InterfaceLanguage.label("未命名人物") : row.character.name)
                        .font(theme.fontBody)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: nameWidth, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(Array(row.cells.enumerated()), id: \.offset) { index, presence in
                Button {
                    jump(row: row, chapterIndex: index)
                } label: {
                    Text(LocalizedStringKey(cellLabel(presence)))
                        .font(.system(size: 10, weight: presence == .present ? .medium : .regular))
                        .foregroundStyle(cellForeground(presence))
                        .frame(width: cellWidth - 6, height: 26)
                        .background(cellColor(presence), in: RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 3)
                }
                .buttonStyle(.plain)
                .disabled(presence == .absent || presence == .unwritten)
            }

            Text(tailText(row))
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .frame(width: tailWidth, alignment: .leading)
                .padding(.leading, 10)
        }
        .frame(height: 36)
    }

    private func cellLabel(_ presence: MatrixPresence) -> String {
        switch presence {
        case .present: "在场"
        case .mentioned: "提及"
        case .absent: ""
        case .unwritten: "未写"
        }
    }

    private func cellForeground(_ presence: MatrixPresence) -> Color {
        switch presence {
        case .present: .white
        case .mentioned: theme.warning
        case .absent: theme.textTertiary
        case .unwritten: theme.textTertiary.opacity(0.7)
        }
    }

    private func cellColor(_ presence: MatrixPresence) -> Color {
        switch presence {
        case .present: theme.accent.opacity(0.85)
        case .mentioned: theme.warning.opacity(0.2)
        case .absent: theme.border.opacity(0.25)
        case .unwritten: Color.clear
        }
    }

    private func tailText(_ row: CharacterMatrixRow) -> String {
        guard let first = row.firstChapterIndex, let last = row.lastChapterIndex else {
            return InterfaceLanguage.label("还没出场")
        }
        return String(
            format: InterfaceLanguage.label("初 %lld · 末 %lld · 空 %lld"),
            first + 1, last + 1, row.longestGap
        )
    }

    private func jump(row: CharacterMatrixRow, chapterIndex: Int) {
        guard let project = session.project,
              let node = CharacterMatrixBuilder.node(
                for: row.character,
                chapterIndex: chapterIndex,
                in: project
              ) else { return }
        session.selectedNodeID = node.id
        session.focusedChapterID = node.chapterID
        session.focusedCharacterID = nil
        session.viewMode = .outline
    }
}
