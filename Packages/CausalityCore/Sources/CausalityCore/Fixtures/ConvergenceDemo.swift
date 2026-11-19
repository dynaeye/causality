import Foundation

/// 验收用例用的最小项目：两条路接到同一个结局。
///
/// 阿禾捞起河灯 → 梁婆婆认出河灯 → 两个选项：守密 / 问镇民 → 同一个结局「旧渡口的信」。
public enum ConvergenceDemo {
    public struct Script: Sendable {
        public var project: StoryProject
        public var chapterID: ChapterID
        public var secondChapterID: ChapterID
        public var lantern: NodeID
        public var grandaunt: NodeID
        public var keepSecret: NodeID
        public var askTownsfolk: NodeID
        public var ending: NodeID
        public var keepSecretLabel: String
        public var askTownsfolkLabel: String
        public var causeLabel: String
    }

    // 计算属性：界面语言在调用 make() 之前才定，写死成 let 会拿到旧值。
    public static var keepSecretLabel: String { CoreText.text("阿禾答应替寄信人守密") }
    public static var askTownsfolkLabel: String { CoreText.text("阿禾拿河灯去问镇民") }
    public static var causeLabel: String { CoreText.text("旧渡口只有梁婆婆替人捎过家书") }

    public static func make(
        seed: UInt64 = 0xA11CE,
        localize: (String) -> String = { CoreText.localize($0) }
    ) -> Script {
        let keepSecretLabel = localize("阿禾答应替寄信人守密")
        let askTownsfolkLabel = localize("阿禾拿河灯去问镇民")
        let causeLabel = localize("旧渡口只有梁婆婆替人捎过家书")
        var builder = ProjectBuilder(
            seed: seed,
            title: localize("河灯里的字"),
            logline: localize("一盏逆水漂来的河灯，灯底是母亲的字。"),
            chapterTitle: localize("第一章")
        )
        let chapterID = builder.project.chapters[0].id

        let ahe = builder.addCharacter(
            name: localize("阿禾"),
            summary: localize("替人捎信的姑娘。")
        )
        let liang = builder.addCharacter(
            name: localize("梁婆婆"),
            summary: localize("旧渡口最后一位船娘。")
        )
        let ferry = builder.addPlace(
            name: localize("旧渡口"),
            summary: localize("只剩半截石阶。")
        )
        let lore = builder.addSetting(
            title: localize("母亲离镇是因为欠信"),
            text: localize("母亲当年替人捎信，欠了人情才离镇。"),
            confirmed: true,
            locked: true
        )

        let lantern = builder.addNode(
            title: localize("阿禾捞起河灯"),
            summary: localize("一盏河灯逆水漂来，灯底写着母亲的字。"),
            body: localize("夜河上漂来一盏河灯。阿禾伸手把它捞起，翻过来，灯底是母亲的字。"),
            chapterID: chapterID,
            isEntry: true,
            characters: [ahe],
            places: [ferry],
            position: CanvasPoint(x: 0, y: 0)
        )
        let grandaunt = builder.addNode(
            title: localize("梁婆婆认出河灯"),
            summary: localize("旧渡口只有梁婆婆替人捎过家书。"),
            body: localize("梁婆婆接过灯，指腹在灯骨上摩了一下。她说这灯是她扎的。"),
            chapterID: chapterID,
            characters: [ahe, liang],
            places: [ferry],
            position: CanvasPoint(x: 260, y: 0)
        )
        let keepSecret = builder.addNode(
            title: localize("梁婆婆交出半封旧信"),
            summary: localize("阿禾答应守密，梁婆婆交出半封旧信。"),
            body: localize("梁婆婆从船篷底下摸出一封信，撕掉的那半在她自己手里。"),
            chapterID: chapterID,
            position: CanvasPoint(x: 520, y: -120)
        )
        let askTownsfolk = builder.addNode(
            title: localize("赶集的人认出纸张"),
            summary: localize("卖纸老人认出纸张来自旧渡口。"),
            body: localize("赶集的人围着河灯看。卖纸的老人伸手摸了摸，说这纸他送过。"),
            chapterID: chapterID,
            position: CanvasPoint(x: 520, y: 120)
        )
        let ending = builder.addNode(
            title: localize("旧渡口的信"),
            kind: .ending,
            summary: localize("阿禾读懂母亲当年离镇的缘由，把回信交给梁婆婆。"),
            body: localize("旧渡口只剩半截石阶。阿禾把两半信对起来，母亲的字终于读得通。")
                + "\n"
                + localize("她没有把信带走，交给了梁婆婆。"),
            chapterID: chapterID,
            characters: [ahe, liang],
            places: [ferry],
            settings: [lore],
            position: CanvasPoint(x: 800, y: 0)
        )
        builder.attach(lore, to: ending)

        builder.connect(lantern, to: grandaunt, kind: .cause, label: causeLabel)
        builder.connect(grandaunt, to: keepSecret, kind: .choice, label: keepSecretLabel)
        builder.connect(grandaunt, to: askTownsfolk, kind: .choice, label: askTownsfolkLabel)
        builder.connect(
            keepSecret,
            to: ending,
            kind: .cause,
            label: localize("梁婆婆交出半封旧信，阿禾独自去渡口")
        )
        builder.connect(
            askTownsfolk,
            to: ending,
            kind: .plain,
            label: localize("赶集的人认出纸张来自旧渡口，众人一同前往")
        )

        // 第二章用来展示故事板的横向展开：一张正式场景加一张还没想清楚的念头。
        let secondChapter = Chapter(title: localize("第二章"))
        builder.apply(ProjectMutations.appendChapter(secondChapter, to: builder.project))

        let letter = builder.addNode(
            title: localize("梁婆婆把灯放回河里"),
            summary: localize("她把灯推回水上，没有说再见。"),
            body: localize("梁婆婆把灯推回水上。灯顺流走了，她在岸上站了很久。"),
            chapterID: secondChapter.id,
            characters: [liang],
            places: [ferry],
            position: CanvasPoint(x: 1080, y: 0)
        )
        builder.connect(
            ending,
            to: letter,
            kind: .cause,
            label: localize("信送出去之后，她回到渡口")
        )
        _ = builder.addNode(
            title: localize("要不要写她父亲？"),
            summary: localize("父亲这条线一直没落地，先留一张卡。"),
            chapterID: secondChapter.id,
            status: .idea,
            position: CanvasPoint(x: 1080, y: 200)
        )

        return Script(
            project: builder.finalized(),
            chapterID: chapterID,
            secondChapterID: secondChapter.id,
            lantern: lantern,
            grandaunt: grandaunt,
            keepSecret: keepSecret,
            askTownsfolk: askTownsfolk,
            ending: ending,
            keepSecretLabel: keepSecretLabel,
            askTownsfolkLabel: askTownsfolkLabel,
            causeLabel: causeLabel
        )
    }
}
