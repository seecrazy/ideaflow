# 灵感集 IdeaFlow

随时随地记录任何想法/素材,用最快的速度重新找到它。

本地优先的 iPhone 灵感捕捉与管理系统:记录在 3 秒内完成、强杀不丢草稿、状态流转全程留痕、一 万条数据搜索 ≤ 200ms。

## 这是什么

一个装在口袋里的"灵感收件箱":

- **记的快**:首页常驻输入条,点开就能打字;语音边说边转写、拍照、粘链接,一键全挂到同一条灵感上
- **不丢失**:输入即存草稿,App 被杀、崩溃后重开都能找回;删除先进回收站,默认 30 天可恢复
- **找的快**:全文搜索(标题/正文/语音转写/链接标题/文件名)+ 拼音首字母 + 状态/类型/标签/时间组合筛选
- **有始有终**:每条灵感有六态生命周期(草稿→待处理→已采纳/已拒绝→已废弃/已归档),每次流转写审计日志,批量操作也逐条留痕

## 怎么用

```bash
open IdeaFlow.xcodeproj        # Xcode 里选 IdeaFlow scheme,⌘R 即跑
```

想看效果又懒得先记一堆?带演示数据启动:

```bash
zsh scripts/shoot.sh           # 或:Xcode scheme 参数加 -seedDemo
```

| 操作 | 入口 |
|------|------|
| 记一条 | 首页底部输入条,输入后点右侧 ↑ |
| 语音速记 | 输入条 🎤 → 说话 → 停止(可先转写)→ ✓ |
| 存图片 | 输入条聚焦后 📷,相册多选 |
| 存链接 | 输入条聚焦后 🔗,粘贴网址自动抓标题摘要 |
| 改状态 | 详情页顶部胶囊 → 选目标状态(只列合法流转);或列表左滑 |
| 多选批量 | 长按任意卡片 → 多选 |
| 置顶/删除 | 长按卡片快捷菜单;左滑删除 |
| 搜索 | 搜索 Tab;支持"支付"(中文)、"zhifu"(全拼)、"zf"(首字母) |
| 回收站 | 首页右上角 🗑;设置里可改保留时长 |
| 导出 | 设置 → 导出全部(Markdown / JSON) |
| 每晚回顾 | 设置 → 通知 → 每日回顾提醒 |
| 隐私 | 设置 → Face ID 锁;数据文件始终完成级加密落盘 |

## 验证

```bash
xcodebuild -project IdeaFlow.xcodeproj -scheme IdeaFlow \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

58 个单元测试 + 3 个端到端 UI 测试(记录→改状态→搜索、草稿强杀恢复、回收站恢复),含一 万条 FTS 搜索 ≤ 200ms 性能断言。

## 设计与现状

- 完整设计文档(用户原始 spec,唯一权威):[DESIGN.md](DESIGN.md)
- 实施进度:[PROGRESS.md](PROGRESS.md)
- 已知技术债与未落地项:[DEBT.md](DEBT.md)

技术栈:SwiftUI / Core Data(程序化模型)/ SQLite FTS5 + 拼音(CFStringTransform 零依赖)/ Speech / AVFoundation / LinkPresentation。iOS 17+。
