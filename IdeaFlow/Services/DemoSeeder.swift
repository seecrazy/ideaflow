import Foundation
import CoreData

/// 演示种子(Task 12 完整化):多状态/多形态/相对时间分布
@MainActor
enum DemoSeeder {
    static func seedIfNeeded(store: IdeaStore) {
        let req = Idea.fetchRequest()
        req.predicate = NSPredicate(format: "seedNote != nil")
        // 占位检查:以"总条数为 0"作为未播种判定,避免 SeedNote 字段
        let any = (try? store.ctx.count(for: Idea.fetchRequest())) ?? 0
        guard any == 0 else { return }
        _ = req
        seed(store: store)
    }

    static func seed(store: IdeaStore) {
        let calendar = Calendar.current

        func back(_ days: Double, _ hours: Double = 0) -> Date {
            Date().addingTimeInterval(-days * 86400 - hours * 3600)
        }

        struct Row {
            let text: String
            let tags: [String]
            let status: IdeaStatus
            let created: Date
        }

        let rows: [Row] = [
            Row(text: "做一个语音速记的快捷方式\n走路时也能把想法说进去,自动转写挂到当天", tags: ["产品", "语音"], status: .draft, created: back(0, 0.03)),
            Row(text: "支付流程优化\n结账从 4 步压到 2 步,转化率应该能提一截,重点看失败重试的文案", tags: ["产品", "支付"], status: .adopted, created: back(0, 5)),
            Row(text: "读书:卡片笔记写作法\n真正的灵感管理不是收集,而是定期回顾与连接", tags: ["读书"], status: .pending, created: back(1, 2)),
            Row(text: "给爸妈做一个一键拨号磁贴\n桌面小组件 + 大字体", tags: ["家庭", "设计"], status: .adopted, created: back(2)),
            Row(text: "周末骑行路线:环湖\n早起出发,带两瓶水", tags: ["生活"], status: .archived, created: back(4)),
            Row(text: "面试题:如何设计一个秒杀系统\n削峰、缓存、限流三板斧,重点是库存的一致性", tags: ["技术"], status: .pending, created: back(5, 3)),
            Row(text: "把博客的暗色模式重做\n现在的对比度太低了,正文 15px 起步", tags: ["设计", "博客"], status: .rejected, created: back(7)),
            Row(text: "学 Swift Charts\n给跑步数据做一张周报图", tags: ["技术", "健康"], status: .abandoned, created: back(9, 6)),
            Row(text: "语音备忘:开会时老板提的三个指标\n留存、时长、分享率", tags: ["工作"], status: .draft, created: back(12)),
            Row(text: "想写一篇《慢决策》\n快时代里,慢一点反而赢得多", tags: ["写作"], status: .pending, created: back(15, 1)),
            Row(text: "阳台种小番茄\n春天播种,60 天结果", tags: ["生活"], status: .draft, created: back(18)),
            Row(text: "整理 2026 想去的五个城市\n京都、里斯本、清迈、大理、札幌", tags: ["旅行"], status: .pending, created: back(21, 8)),
        ]

        for row in rows {
            if let idea = store.capture(text: row.text, tagNames: row.tags) {
                idea.createdAt = row.created
                idea.updatedAt = row.created
                idea.statusChangedAt = row.created
                switch row.status {
                case .draft: break
                case .pending:
                    _ = store.transition(idea, to: .pending)
                case .adopted:
                    _ = store.transition(idea, to: .pending)
                    _ = store.transition(idea, to: .adopted)
                case .rejected:
                    _ = store.transition(idea, to: .pending)
                    _ = store.transition(idea, to: .rejected)
                case .abandoned:
                    _ = store.transition(idea, to: .pending)
                    _ = store.transition(idea, to: .abandoned)
                case .archived:
                    _ = store.transition(idea, to: .pending)
                    _ = store.transition(idea, to: .adopted)
                    _ = store.transition(idea, to: .archived)
                }
                try? store.persistence.saveIfNeeded(store.ctx)
            }
        }
    }
}
