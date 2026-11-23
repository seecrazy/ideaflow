import SwiftUI

/// 我的/设置(DESIGN §9.5):存储、导出、回收站保留、提醒、Face ID、关于。
struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var usage: MediaStore.StorageUsage = MediaStore.StorageUsage()
    @State private var retentionDays = UserDefaults.standard.integer(forKey: "recycleRetentionDays")
    @State private var reminderOn = UserDefaults.standard.bool(forKey: ReminderService.enabledKey)
    @State private var remindHour = UserDefaults.standard.integer(forKey: ReminderService.hourKey)
    @State private var remindMinute = UserDefaults.standard.integer(forKey: ReminderService.minuteKey)
    @State private var lockEnabled = UserDefaults.standard.bool(forKey: AppLockService.enabledKey)
    @State private var exportURL: URL?
    @State private var rebuilding = false

    private let reminder = ReminderService()

    var body: some View {
        List {
            storageSection
            dataSection
            reminderSection
            privacySection
            aboutSection
        }
        .navigationTitle("我的")
        .onAppear {
            usage = env.mediaStore.computeUsage()
            if retentionDays <= 0 { retentionDays = 30 }
            if remindHour == 0 { remindHour = 20; remindMinute = 30 }
        }
        .sheet(item: $exportURL) { url in
            ActivityShareSheet(items: [url])
        }
    }

    // MARK: - 存储

    private var storageSection: some View {
        Section {
            LabeledContent("图片") { Text(ByteCountFormatter.string(fromByteCount: usage.images, countStyle: .file)) }
            LabeledContent("语音") { Text(ByteCountFormatter.string(fromByteCount: usage.audio, countStyle: .file)) }
            LabeledContent("其他") { Text(ByteCountFormatter.string(fromByteCount: usage.others, countStyle: .file)) }
            LabeledContent("合计") {
                Text(usage.humanReadable).font(.system(size: 15, weight: .semibold))
            }
            Button {
                rebuildIndex()
            } label: {
                HStack {
                    Label("重建搜索索引", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if rebuilding { ProgressView() }
                }
            }
            .disabled(rebuilding)
        } header: {
            Text("存储")
        } footer: {
            Text("索引与数据分开存放,重建不影响数据,用于修复搜索异常")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section("数据") {
            Picker("回收站保留", selection: $retentionDays) {
                Text("7 天").tag(7)
                Text("30 天").tag(30)
                Text("90 天").tag(90)
            }
            .onChange(of: retentionDays) { _, days in
                UserDefaults.standard.set(days, forKey: "recycleRetentionDays")
            }

            NavigationLink { RecycleBinView() } label: {
                Label("回收站", systemImage: "trash")
            }

            Button {
                export(format: .markdown)
            } label: {
                Label("导出全部(Markdown)", systemImage: "square.and.arrow.up")
            }
            Button {
                export(format: .json)
            } label: {
                Label("导出全部(JSON)", systemImage: "square.and.arrow.up")
            }
        }
    }

    private enum ExportFormat { case markdown, json }

    private func export(format: ExportFormat) {
        let req = Idea.fetchRequest()
        req.predicate = NSPredicate(format: "deletedAt == nil")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let ideas = (try? env.store.ctx.fetch(req)) ?? []
        guard !ideas.isEmpty else { return }
        do {
            exportURL = format == .markdown
                ? try ExportService.exportMarkdown(ideas: ideas)
                : try ExportService.exportJSON(ideas: ideas)
        } catch {
            // 导出失败静默,后续版本加提示
        }
    }

    // MARK: - 提醒

    private var reminderSection: some View {
        Section {
            Toggle("每日回顾提醒", isOn: $reminderOn)
                .onChange(of: reminderOn) { _, on in
                    reminder.update(enable: on, hour: remindHour, minute: remindMinute)
                }
            if reminderOn {
                DatePicker("提醒时间", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: remindHour, minute: remindMinute, second: 0, of: Date()) ?? Date() },
                    set: { date in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                        remindHour = comps.hour ?? 20
                        remindMinute = comps.minute ?? 30
                        reminder.update(enable: true, hour: remindHour, minute: remindMinute)
                    }
                ), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("通知")
        } footer: {
            Text("每晚提醒你回顾当天记录,整理状态")
        }
    }

    // MARK: - 隐私

    private var privacySection: some View {
        Section {
            Toggle("Face ID 锁", isOn: $lockEnabled)
                .onChange(of: lockEnabled) { _, on in
                    env.appLock.isEnabled = on
                    if !on { env.appLock.isLocked = false }
                }
        } header: {
            Text("隐私")
        } footer: {
            Text("开启后每次进入 App 需验证面容;数据本身始终以完成保护级别落盘")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本") { Text("1.0 (1)") }
            LabeledContent("本地优先") { Text("数据仅存本机") }
        }
    }

    private func rebuildIndex() {
        rebuilding = true
        env.searchService.rebuildIndexFromStore()
        env.searchService.flushIndex()
        rebuilding = false
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

/// UIActivityViewController 桥
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 回收站(DESIGN §13/§9.5):软删除列表、恢复、彻底删除、保留期倒计时。
struct RecycleBinView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var ideas: [Idea] = []
    @State private var confirmDestroy: Idea?

    var body: some View {
        Group {
            if ideas.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "trash").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("回收站是空的").font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(ideas, id: \.objectID) { idea in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(idea.displayTitle)
                            .font(.system(size: 15, weight: .medium))
                        HStack {
                            Text(idea.status.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(idea.status.swiftUIColor)
                            Spacer()
                            if let deleted = idea.deletedAt {
                                Text("还剩 \(remainingDays(since: deleted)) 天自动清理")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        HStack {
                            Button("恢复") {
                                try? env.store.restore(idea)
                                refresh()
                            }
                            .buttonStyle(.bordered)
                            .tint(Color(env.appTint))
                            Button("彻底删除", role: .destructive) {
                                confirmDestroy = idea
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.system(size: 13))
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            confirmDestroy = idea
                        } label: { Label("彻底删除", systemImage: "trash") }
                        Button {
                            try? env.store.restore(idea)
                            refresh()
                        } label: { Label("恢复", systemImage: "arrow.uturn.backward") }
                        .tint(Color(env.appTint))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("回收站")
        .onAppear { refresh() }
        .confirmationDialog("彻底删除后无法恢复", isPresented: Binding(
            get: { confirmDestroy != nil }, set: { if !$0 { confirmDestroy = nil } }
        ), titleVisibility: .visible) {
            Button("彻底删除", role: .destructive) {
                if let idea = confirmDestroy {
                    env.store.destroyNow(idea)
                    refresh()
                }
                confirmDestroy = nil
            }
        }
    }

    private func remainingDays(since date: Date) -> Int {
        let retention = UserDefaults.standard.integer(forKey: "recycleRetentionDays")
        let days = retention > 0 ? retention : 30
        let elapsed = Date().timeIntervalSince(date) / 86400
        return max(0, days - Int(elapsed))
    }

    private func refresh() {
        ideas = (try? env.store.deletedIdeas()) ?? []
    }
}
