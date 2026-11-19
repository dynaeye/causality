import AppKit
import CoreText
import CausalityCore

/// 打印用 PDF：把大纲排成 A4 分页文档，含正文、连线说明、人物地点与事实设定。
///
/// 与界面共用 `OutlineBuilder` 的推导；走单路线时只排这条路上的人与卡。
enum OutlinePDFExport {
    private static let pageSize = CGSize(width: 595.28, height: 841.89)   // A4
    /// 打印留白：上 64、下 76（给页脚留位置）、左右 52，中缝 26。
    private static let insetTop: CGFloat = 64
    private static let insetBottom: CGFloat = 76
    private static let insetLeft: CGFloat = 52
    private static let insetRight: CGFloat = 52
    private static let gutter: CGFloat = 26

    /// 双栏版心：A4 排双栏后每栏约 232pt，中文 9.5pt 一行 24 字左右。
    private static var columnWidth: CGFloat {
        (pageSize.width - insetLeft - insetRight - gutter) / 2
    }

    private static var columnHeight: CGFloat { pageSize.height - insetTop - insetBottom }

    /// 分栏从左到右；PDF 坐标原点在左下角。
    private static func columnRect(_ column: Int) -> CGRect {
        CGRect(
            x: insetLeft + CGFloat(column) * (columnWidth + gutter),
            y: insetBottom,
            width: columnWidth,
            height: columnHeight
        )
    }

    static func makePDF(
        project: StoryProject,
        route: StoryRoute?,
        packageURL: URL? = nil,
        language: InterfaceLanguage = .current
    ) -> Data? {
        let text = document(project: project, route: route, packageURL: packageURL, language: language)
        guard text.length > 0 else { return nil }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)

        var start = 0
        var page = 1
        let total = text.length
        while start < total {
            context.beginPDFPage(nil)
            context.saveGState()

            var advanced = 0
            for column in 0..<2 {
                guard start < total else { break }
                let rect = columnRect(column)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: start, length: 0),
                    CGPath(rect: rect, transform: nil),
                    nil
                )
                CTFrameDraw(frame, context)
                drawImages(in: frame, context: context, frameOrigin: rect.origin)

                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { break }
                start += visible.length
                advanced += visible.length
            }

            context.restoreGState()
            drawFooter(page: page, in: context)
            context.endPDFPage()

            guard advanced > 0 else { break }
            page += 1
        }
        context.closePDF()
        return data as Data
    }

    private static func drawFooter(page: Int, in context: CGContext) {
        let text = NSAttributedString(
            string: "\(page)",
            attributes: [
                .font: regular(8),
                .foregroundColor: NSColor(white: 0.55, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(text as CFAttributedString)
        context.textPosition = CGPoint(x: pageSize.width - insetRight, y: insetBottom / 2)
        CTLineDraw(line, context)
    }

    // MARK: - 字体

    /// 用能嵌进 PDF 的字体。系统 UI 字体的粗体在 PDF 里不可嵌入，会整段消失。
    private static func regular(_ size: CGFloat) -> NSFont {
        NSFont(name: "PingFangSC-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    private static func bold(_ size: CGFloat) -> NSFont {
        NSFont(name: "PingFangSC-Semibold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    // MARK: - 排版

    private static func document(
        project: StoryProject,
        route: StoryRoute?,
        packageURL: URL?,
        language: InterfaceLanguage
    ) -> NSAttributedString {
        let index = project.makeIndex()
        let outlines = route.map { route in
            OutlineBuilder.build(project: project, index: index, nodes: route.nodeIDs)
                .filter { !$0.rows.isEmpty }
        } ?? OutlineBuilder.build(project: project, index: index)

        let body = NSMutableAttributedString()
        body.append(paragraph(project.title, font: bold(22), color: NSColor(white: 0.1, alpha: 1), after: 6))

        if let route, let ending = index.nodeByID[route.endingID] {
            body.append(paragraph(String(format: language.label("只含通往「%@」的路径。"), ending.title), font: regular(10), color: .gray, after: 8))
        }
        if !project.logline.isEmpty {
            body.append(paragraph(project.logline, font: regular(10), color: .darkGray, after: 14))
        }

        for outline in outlines {
            body.append(paragraph(
                outline.chapterTitle,
                font: bold(15),
                color: NSColor(white: 0.1, alpha: 1),
                before: 12,
                after: 4
            ))
            if !outline.chapterSummary.isEmpty {
                body.append(paragraph(outline.chapterSummary, font: regular(9.5), color: .gray, after: 6))
            }
            for row in outline.rows {
                let indent = CGFloat(row.indent) * 14
                if let incoming = row.incoming {
                    body.append(paragraph(
                        "↳ \(incoming.displayText(localize: language.label))",
                        font: regular(9),
                        color: NSColor(white: 0.45, alpha: 1),
                        indent: indent + 10,
                        after: 1
                    ))
                }
                let titleColor = NSColor(white: row.role == .scene ? 0.1 : 0.4, alpha: 1)
                body.append(paragraph(
                    (row.role == .scene ? "" : "↪ ") + row.nodeTitle,
                    font: row.role == .scene ? bold(11.5) : regular(11),
                    color: titleColor,
                    indent: indent,
                    before: 4,
                    after: 2
                ))

                guard row.role == .scene, let node = index.nodeByID[row.nodeID] else { continue }
                if !node.body.isEmpty {
                    body.append(paragraph(
                        node.body,
                        font: regular(9.5),
                        color: NSColor(white: 0.25, alpha: 1),
                        indent: indent + 10,
                        after: 2,
                        lineSpacing: 2
                    ))
                }
                let extras = entityLines(index: index, node: node, project: project, language: language)
                if !extras.isEmpty {
                    body.append(paragraph(
                        extras,
                        font: regular(9),
                        color: NSColor(white: 0.4, alpha: 1),
                        indent: indent + 10,
                        after: 3
                    ))
                }
                if let packageURL,
                   let assetID = node.coverAssetID,
                   let asset = project.asset(assetID),
                   let image = NSImage(contentsOf: ProjectPackage.assetURL(for: asset, in: packageURL)) {
                    body.append(imageParagraph(image))
                    if !asset.caption.isEmpty {
                        body.append(paragraph(
                            asset.caption,
                            font: regular(8.5),
                            color: NSColor(white: 0.45, alpha: 1),
                            before: 1,
                            after: 9,
                            lineSpacing: 1,
                            align: .center
                        ))
                    }
                }
            }
        }

        if !project.threads.isEmpty {
            body.append(paragraph(language.label("线索"), font: bold(13), color: NSColor(white: 0.1, alpha: 1), before: 14, after: 4))
            for thread in project.threads {
                body.append(paragraph(
                    "\(language.label(thread.kind.displayName)) · \(thread.name)",
                    font: bold(10.5),
                    color: NSColor(white: 0.15, alpha: 1),
                    before: 6,
                    after: 2
                ))
                for point in ThreadSpine.points(for: thread, in: project) {
                    let separator = language.labelSeparator
                    let text = point.entry.text.isEmpty ? "" : "\(separator)\(point.entry.text)"
                    body.append(paragraph(
                        "\(language.label(point.entry.role.displayName))\(separator)\(point.chapterTitle) · \(point.node.title)\(text)",
                        font: regular(9.5),
                        color: NSColor(white: 0.3, alpha: 1),
                        indent: 10,
                        after: 1
                    ))
                }
            }
        }

        let ideas = route == nil ? project.nodes.filter { $0.status == .idea } : []
        if !ideas.isEmpty {
            body.append(paragraph(language.label("灵感卡"), font: bold(13), color: NSColor(white: 0.1, alpha: 1), before: 14, after: 4))
            for idea in ideas {
                body.append(paragraph(
                    "· \(idea.title)" + (idea.summary.isEmpty ? "" : "\(language.labelSeparator)\(idea.summary)"),
                    font: regular(9.5),
                    color: NSColor(white: 0.3, alpha: 1),
                    after: 2
                ))
            }
        }
        return body
    }

    private static func entityLines(
        index: ProjectIndex,
        node: StoryNode,
        project: StoryProject,
        language: InterfaceLanguage
    ) -> String {
        var parts: [String] = []
        let separator = language.labelSeparator
        let list = language.listSeparator
        let characters = node.characterIDs.compactMap { index.characterByID[$0]?.name }
        if !characters.isEmpty { parts.append(language.label("出场") + separator + characters.joined(separator: list)) }
        let places = node.placeIDs.compactMap { index.placeByID[$0]?.name }
        if !places.isEmpty { parts.append(language.label("地点") + separator + places.joined(separator: list)) }
        let settings = project.settings
            .filter { $0.attachedNodeIDs.contains(node.id) || node.settingIDs.contains($0.id) }
            .map(\.title)
        if !settings.isEmpty { parts.append(language.label("事实设定") + separator + settings.joined(separator: list)) }
        return parts.joined(separator: language.columnSeparator)
    }

    /// 配图按栏宽缩放，宽度不超版心、高度不超过 220pt；保持原比例。
    ///
    /// CoreText 不认 NSTextAttachment，用 CTRunDelegate 占位，画完正文后按 run 的位置把图贴上去。
    private static func imageParagraph(_ image: NSImage) -> NSAttributedString {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return NSAttributedString() }
        let maxWidth = columnWidth
        let scale = min(1, maxWidth / size.width, 220 / size.height)
        let box = ImageBox(
            image: image,
            size: CGSize(width: size.width * scale, height: size.height * scale)
        )
        guard let delegate = runDelegate(for: box) else { return NSAttributedString() }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTRunDelegateAttributeName as String): delegate,
            imageAttribute: box,
            .paragraphStyle: style,
            .font: regular(2),
        ]
        return NSAttributedString(string: "\u{FFFC}\n", attributes: attributes)
    }

    private final class ImageBox {
        let image: NSImage
        let size: CGSize

        init(image: NSImage, size: CGSize) {
            self.image = image
            self.size = size
        }
    }

    private static let imageAttribute = NSAttributedString.Key("causal.pdf.imageBox")

    private static func runDelegate(for box: ImageBox) -> CTRunDelegate? {
        let ref = Unmanaged.passRetained(box).toOpaque()
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in
                Unmanaged<ImageBox>.fromOpaque(pointer).release()
            },
            getAscent: { pointer in
                Unmanaged<ImageBox>.fromOpaque(pointer).takeUnretainedValue().size.height
            },
            getDescent: { _ in 0 },
            getWidth: { pointer in
                Unmanaged<ImageBox>.fromOpaque(pointer).takeUnretainedValue().size.width
            }
        )
        guard let delegate = CTRunDelegateCreate(&callbacks, ref) else {
            Unmanaged<ImageBox>.fromOpaque(ref).release()
            return nil
        }
        return delegate
    }

    /// 在已经画完正文的页上补画配图：run 的起点加上行基线，就是图片的左下角。
    private static func drawImages(in frame: CTFrame, context: CGContext, frameOrigin: CGPoint) {
        guard let lines = CTFrameGetLines(frame) as? [CTLine] else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        context.saveGState()
        context.textMatrix = .identity
        for (line, origin) in zip(lines, origins) {
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for run in runs {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let box = attributes[imageAttribute] as? ImageBox else { continue }
                let range = CTRunGetStringRange(run)
                var secondary: CGFloat = 0
                let offset = CGFloat(CTLineGetOffsetForStringIndex(line, range.location, &secondary))
                let rect = CGRect(
                    x: frameOrigin.x + origin.x + offset,
                    y: frameOrigin.y + origin.y,
                    width: box.size.width,
                    height: box.size.height
                )
                guard let cgImage = box.image.cgImage(
                    forProposedRect: nil,
                    context: nil,
                    hints: nil
                ) else { continue }
                context.draw(cgImage, in: rect)
            }
        }
        context.restoreGState()
    }

    private static func paragraph(
        _ text: String,
        font: NSFont,
        color: NSColor,
        indent: CGFloat = 0,
        before: CGFloat = 0,
        after: CGFloat = 0,
        lineSpacing: CGFloat = 0,
        align: NSTextAlignment = .left
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineSpacing = lineSpacing
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text + "\n", attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }
}
