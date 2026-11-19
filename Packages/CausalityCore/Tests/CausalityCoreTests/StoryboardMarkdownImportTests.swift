import Foundation
import Testing
@testable import CausalityCore

@Suite("文字故事板导入")
struct StoryboardMarkdownImportTests {
    private static let sample = """
    # 《测试镇》开篇故事板 · 第一程

    版本 v0.1 · 文字策划草案

    **本章从玩家入镇写到第一次远游归家。** 下文日程是演出节奏。

    ## 第一幕 · 入镇

    | 节点与时机 | 玩家眼前发生什么 | 玩家亲手做什么 | 留下什么，怎样引出下一场 |
    |---|---|---|---|
    | S01 入镇，当日下午 | 雨刚停，玩家带着行李来投奔房东。 | 放下行囊，帮她收药。 | 拿到自己的房门钥匙。月露叶是认得的第一味草药。 |
    | S02 见法，次日清晨 | 城北来的老匠人在小院避雨。 | 转动叶片，看露珠逆流。 | 玩家第一次看见这门手艺。老匠人约他上山。 |

    ## 第二幕 · 上城北山坡

    | 节点与时机 | 玩家眼前发生什么 | 玩家亲手做什么 | 留下什么，怎样引出下一场 |
    |---|---|---|---|
    | S03 求法，接受邀约后的清晨 | 从北口沿小路上城北山坡。 | 依呼吸引火，接住一滴青露。 | 学会第一门手艺。师傅借出小炉。 |

    ## 人物

    | 名字 | 简介 |
    |---|---|
    | 房东 | 把靠河的小屋腾给玩家。 |
    | 老匠人 | 城北来的匠人，邀玩家上山学第一门手艺。 |

    ## 地点

    | 名字 | 简介 |
    |---|---|
    | 城北山坡 | 镇北，小路接石阶，半山有间作坊。 |

    ## 设定

    | 名字 | 说明 |
    |---|---|
    | 第一门手艺 | 从看材料颜色变到收手，整套动作在几分钟里做完。 |

    ## 四向出口

    | 出口 | 相邻地块与地形连接 | 玩家为什么走这条路 |
    |---|---|---|
    | 北口 | 城北山坡，小路接石阶。 | 带鲜叶拜师。 |

    ## 回溯与修改

    - **人物因果**：S01 房东提供居所 → S03 上山授法。
    """

    @Test("章节按标题分，卡片按表格行序")
    func chaptersAndCards() throws {
        let project = try StoryboardMarkdown.makeProject(fromMarkdown: Self.sample, title: "测试镇")
        #expect(project.title == "测试镇")
        #expect(project.chapters.count == 2)
        #expect(project.chapters.map(\.title) == ["第一幕 · 入镇", "第二幕 · 上城北山坡"])

        let cards = project.nodes.filter { $0.status == .draft }
        #expect(cards.count == 3)
        #expect(cards.map(\.title) == ["S01 入镇", "S02 见法", "S03 求法"])
        #expect(cards[0].isEntry)
        #expect(cards[0].chapterID == project.chapters[0].id)
        #expect(cards[2].chapterID == project.chapters[1].id)
        #expect(cards[0].annotation == "当日下午")
        #expect(cards[0].body.contains("眼前：雨刚停"))
        #expect(cards[0].body.contains("动手：放下行囊"))
        #expect(cards[0].body.contains("留下：拿到自己的房门钥匙"))
        #expect(project.logline.hasPrefix("本章从玩家入镇写到第一次远游归家。"))
    }

    @Test("按行序串成因果链，连线取「留下」首句")
    func chain() throws {
        let project = try StoryboardMarkdown.makeProject(fromMarkdown: Self.sample)
        let cards = project.nodes.filter { $0.status == .draft }
        #expect(project.edges.count == 2)

        let first = project.edges.first { $0.from == cards[0].id }
        #expect(first?.to == cards[1].id)
        #expect(first?.label == "拿到自己的房门钥匙")

        let second = project.edges.first { $0.from == cards[1].id }
        #expect(second?.to == cards[2].id)
        #expect(second?.label == "玩家第一次看见这门手艺")
    }

    @Test("人物、地点、设定按文内名字挂到卡上")
    func library() throws {
        let project = try StoryboardMarkdown.makeProject(fromMarkdown: Self.sample)
        let cards = project.nodes.filter { $0.status == .draft }

        let aunt = try #require(project.characters.first { $0.name == "房东" })
        let elder = try #require(project.characters.first { $0.name == "老匠人" })
        #expect(cards[0].characterIDs.contains(aunt.id))
        #expect(!cards[0].characterIDs.contains(elder.id))
        #expect(cards[1].characterIDs.contains(elder.id))

        let mountain = try #require(project.places.first { $0.name == "城北山坡" })
        #expect(cards[2].placeIDs.contains(mountain.id))

        let method = try #require(project.settings.first { $0.title == "第一门手艺" })
        #expect(method.attachedNodeIDs.contains(cards[2].id))
        #expect(!method.attachedNodeIDs.contains(cards[0].id))
    }

    @Test("其他表与条目进灵感卡，不占故事板的列")
    func referenceCards() throws {
        let project = try StoryboardMarkdown.makeProject(fromMarkdown: Self.sample)
        let ideas = project.nodes.filter { $0.status == .idea }
        #expect(ideas.map(\.title) == ["北口", "人物因果"])
        #expect(ideas[0].body.contains("相邻地块与地形连接：城北山坡，小路接石阶。"))
        #expect(ideas[1].body.contains("S01 房东提供居所"))
        #expect(ideas.allSatisfy { $0.chapterID == nil })
    }

    @Test("英文表头与卡片标签跟随当前语言")
    func englishHeaderAndLabels() throws {
        let english: (String) -> String = { key in
            switch key {
            case "节点与时机": return "Beat and Timing"
            case "眼前：%@": return "Sees: %@"
            case "动手：%@": return "Does: %@"
            case "留下：%@": return "Leaves: %@"
            default: return key
            }
        }

        let markdown = """
        # The Lantern

        ## Act One

        | Beat and Timing | What the player sees | What the player does | What remains |
        |---|---|---|---|
        | S01 Arrival, afternoon | Rain stops over the flooded square. Mira waits by the door. | Cross the square. | A key to the north gate. |

        ## 人物

        | 名字 | 简介 |
        |---|---|
        | Mira | Runs the lantern shop. |
        """

        #expect(MarkdownImport.detectMode(markdown, localize: english) == .storyboard)
        let result = try MarkdownImport.makeProject(
            fromMarkdown: markdown,
            title: "The Lantern",
            localize: english
        )
        #expect(result.mode == .storyboard)
        #expect(result.project.characters.count == 1)

        let card = try #require(result.project.nodes.first { $0.status == .draft })
        #expect(card.body.contains("Sees: Rain stops"))
        #expect(card.body.contains("Does: Cross the square"))
        #expect(card.body.contains("Leaves: A key"))
        #expect(card.characterIDs.contains(result.project.characters[0].id))
    }

    @Test("没有节点表的文本会被拒绝")
    func rejectsEmptyInput() {
        #expect(throws: StoryboardMarkdown.ImportError.self) {
            try StoryboardMarkdown.makeProject(fromMarkdown: "# 只有标题\n\n没有表格。")
        }
    }
}
