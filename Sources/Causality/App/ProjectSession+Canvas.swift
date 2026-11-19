import CausalityCore

extension ProjectSession {
    /// 故事菜单：把故事图按阅读顺序排成蛇形，撤销一笔就能还原原样。
    func arrangeCanvas(columns: Int = CanvasLayout.defaultColumns) {
        guard let project else { return }
        let operations = CanvasLayout.arrange(project: project, columns: columns)
        guard !operations.isEmpty else { return }
        apply(operations, name: "重排故事图")
    }
}

extension ProjectSession {
    /// 大纲里收起 / 展开一章。
    func toggleChapterCollapse(_ id: ChapterID) {
        if collapsedChapters.contains(id) {
            collapsedChapters.remove(id)
        } else {
            collapsedChapters.insert(id)
        }
    }

    func isCollapsed(_ id: ChapterID) -> Bool {
        collapsedChapters.contains(id)
    }
}
