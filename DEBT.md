# DEBT — 技术债与未落地项

> 明知未做/部分做的,一律在此入账。原则:部分修复=未修复。

## P0(下阶段主线)

### CloudKit 同步本体
- 状态:数据侧就绪(`syncStateRaw`/`remoteAssetID` 字段、属性胜出合并策略、软删除优先结构),同步循环未接
- 阻塞:需要付费开发者账号 + 双设备验证;NSPersistentCloudKitContainer 替换 NSPersistentContainer 是小改,验证冲突合并(DESIGN 验收 6)是真工作
- 解法:接入 NSPersistentCloudKitContainer → 双设备离线编辑用例 → 同步诊断页

### Share Extension(设计 4.1 P0)
- 状态:未做。从其他 App 收藏链接/图片的入口
- 解法:xcodegen/pbxproj 加扩展 target + App Group(附件目录与 store 迁 App Group 容器)

## P1

| 项 | 状态 | 解法 |
|----|------|------|
| 锁屏小组件 / 控制中心 / Siri / 动作按钮 | 未做(设计 4.1 P1) | WidgetKit extension + App Intents("记录灵感" intent 直开输入条) |
| 智能视图(SavedFilter) | 实体已建模,UI 未接 | 搜索页"保存当前筛选"→ 首页顶部 chips 区 |
| 语音实时转写(边说边显) | 当前为录完转写;Speech 流式 API 已封装 | VoiceCaptureSheet 接 SFSpeechAudioBufferRecognitionRequest |
| 冷启动埋点(≤1.2s 验收) | 未埋点;当前无数据 | os_signalt 埋点 + Instruments 验证 |
| 拼音多音字 | CFStringTransform 单读音(如"重"恒 chong) | 遇到实际 case 再评估词级转换 |

## P2(含终审 Minor 入账,2026-11-23)

- FTS 查询在主线程同步执行:当前数据量 ms 级;数据量大后搜索防抖会掉帧 → 查询移后台队列,结果回主线程
- CJK 单字查询零命中(bigram 索引固有):补 unigram 索引或 LIKE 兜底
- 多图保存主线程串行压缩:移后台队列+进度
- 首页缺类型/标签/时间筛选栏(DESIGN 9.1):与智能视图一并接
- 批量操作缺加标签/导出(DESIGN 5.7)
- 详情页已有音频的"补转写"按钮(新录语音可转写,历史音频不行)
- 标签重命名/删除/移除绕过 IdeaStore 单通道(不触发索引更新;当前 tags 入索引后影响变为真实,需走 onIdeaChanged)
- 智能视图(SavedFilter UI)——终审 #21 补记裁决:Task 8 原文含智能视图 chips,实施时降级入 DEBT(与首页筛选栏耦合,一并做)

- 标签合并(设计 §7:重命名/删除/颜色已做,合并未做)
- 图片标注/裁剪编辑器(§8)
- 截图监听导入(§4.4:userDidTakeScreenshotNotification)
- 存储不足预检(§13:保存前检查可用空间)
- 崩溃率监控 Crashlytics(需第三方账号;当前以测试全绿替代)
- 手动拖拽排序(sortOrder 字段已有,UI 未接)
- FAB 悬浮按钮(已被常驻输入条覆盖单手场景,如需再加)
- 自动标签建议(§7,可选功能)

## 明确不做(设计偏离记录)

- 键盘预热池(设计 §4.2):过度工程,SwiftUI focus 延迟实测可接受;如真机测量超 300ms 再上
- 状态色"已废弃/已归档"深色版在暗背景对比度低:忠实 DESIGN 5.3 色板,语义即低调;不擅改
