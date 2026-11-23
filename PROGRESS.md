# PROGRESS — 灵感集 IdeaFlow

> 进度事实源。最新状态:本地完整版 v1.0 已交付(2026-11-23)。

## 当前状态

| 维度 | 状态 |
|------|------|
| 单元测试 | 63/63 绿(状态机/持久化/Store/草稿/搜索含 10k 性能/媒体/导出/终审回归集) |
| UI 测试 | 3/3 绿(记录→状态→搜索 / 草稿强杀恢复 / 回收站恢复) |
| 视觉验收 | 9 页截图逐张目检通过(亮 6 + 深 3) |
| 本地提交 | main 分支,未推送(用户自行控制) |
| 平台 | iOS 17+,Xcode 27.2,iPhone 18 Pro 模拟器验证 |

## 已交付(按计划 14 任务)

1. 工程脚手架(objectVersion 77 同步组,三 target)
2. 状态机域模型(6 态流转表 + 深浅双值色板 + 审计来源)
3. Core Data 程序化模型(五实体/级联/唯一约束/索引)+ 文件保护
4. IdeaStore 单通道(零必填 capture / 强制审计 transition / 批量 / 软删除回收站 / 过期清理)
5. 草稿保护(UserDefaults,500ms 节流 + 失焦即存)
6. 三层搜索(FTS5 独立索引库 + CJK bigram 展开 + CFStringTransform 拼音 + 查询净化)
7. 媒体服务(图片 2048/0.8 缩略 400/0.7、AAC 64k 单声道、链接 5s 超时降级、MD/JSON 导出)
8. 首页 UI(常驻输入条状态机/附件待提交区/chips/左滑/多选/草稿横幅)
9. 详情页(胶囊流转+备注/编辑自动保存/附件区/标签/日志折叠/分享导出)
10. 搜索页(防抖 250ms/历史/热门标签/多维筛选/高亮/空态清筛)
11. 标签页(计数/重命名/颜色/层级/入点子列表)、设置(存储/重建索引/保留时长/导出/提醒/Face ID)、回收站
12. 种子演示 + 9 页截图目检
13. XCUITest 端到端 3 用例
14. 文档(README/PROGRESS/DEBT)

## 终审修复(独立 subagent 整分支审查后)

- Critical:纯附件(语音/图片/链接)保存静默失败 → 零必填占位 + 落盘失败保留待提交区并明示
- 首页保存通知 observer 生命周期 bug(push 一次后首页停更)
- 语音转写授权阻塞主线程 → async 化;来电中断未实现却声称已做 → 真 AVAudioSession interruption 监听
- 拼音带空格查询零命中;标签词不入搜索索引(FTS 加 tags 列+旧库迁移)
- 缩略图主线程同步解码 → NSCache(50MB)+后台解码
- 搜索历史被中间前缀污染;清词留筛选时进度条永挂
- 10 项 Minor 入 DEBT.md P2

## 过程中修掉的真 bug

- 卡片标题/正文派生属性互相调用 → 无限递归栈溢出白屏(目检发现)
- `onLongPressGesture` 吞掉 NavigationLink 点击 → 详情页不可达(UITest 发现,改 contextMenu 后符合设计 5.5)
- 关系构建器反向一律 to-one → 多对多 tags 崩溃(单测发现)
- FTS unicode61 对连续汉字成单 token → 中文子串搜索失效(索引/查询双侧 bigram 展开)

## 坑位备忘

- simctl screenshot 冷启动后立刻拍会抓到空白过渡帧:sleep≥5 且同进程复拍校验
- Read 工具在本环境把图片转 CDN URL,视觉审查走 analyze_image(jpg 可靠,偶发 1210 重转一次即可)
- xcresulttool 路径要用精确 bundle 名(2026.11.23 带点)
- 测试中 AVAsset 读假字节音频会抛 ObjC 异常:测试数据用 AVAudioFile 生成真 AAC
- Bash cwd 会漂移:IdeaProjects 下操作一律绝对路径

## 下一步建议

见 DEBT.md 优先级排序;CloudKit 同步与 Share Extension 为下一阶段主线。
