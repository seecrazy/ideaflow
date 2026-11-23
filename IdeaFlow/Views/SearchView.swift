import SwiftUI
import CoreData

/// 搜索页(DESIGN 6.4/9.3):自动聚焦、历史、热门标签、多维筛选、防抖 250ms、高亮、空态。
struct SearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @FocusState private var focused: Bool

    @State private var query = ""
    @State private var filter = SearchFilter()
    @State private var hits: [SearchService.SearchHit] = []
    @State private var searched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var historyTask: Task<Void, Never>?
    @State private var sortByTime = false
    @State private var allTags: [Tag] = []

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty && filter.isEmpty {
                idleContent
            } else {
                filterBar
                resultsSection
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索灵感/拼音/标签")
        .autocorrectionDisabled()
        .onChange(of: query) { _, text in
            historyTask?.cancel()
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                // 清词但保留筛选:立即出结构化结果(终审 #11)
                if !filter.isEmpty { runSearch() } else { searched = false }
            } else {
                scheduleSearch(text)
            }
        }
        .onAppear {
            refreshTags()
        }
        .navigationTitle("搜索")
        .accessibilityIdentifier("search_page")
    }

    // MARK: - 空闲态:历史 + 热门标签

    private var idleContent: some View {
        Group {
            let history = env.searchService.history()
            if !history.isEmpty {
                Section {
                    HStack {
                        Text("搜索历史").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("清空", role: .destructive) {
                            env.searchService.clearHistory()
                        }
                        .font(.system(size: 13))
                    }
                    .listRowSeparator(.hidden)

                    chipsRow(items: history, removable: true) { term in
                        query = term
                        scheduleSearch(term, immediate: true)
                    } onRemove: { term in
                        env.searchService.removeHistory(term)
                    }
                    .listRowSeparator(.hidden)
                }
            }

            if !allTags.isEmpty {
                Section {
                    Text("全部标签").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                    chipsRow(items: allTags.map { "#\($0.name)" }, removable: false) { term in
                        query = String(term.dropFirst())
                        scheduleSearch(query, immediate: true)
                    }
                    .listRowSeparator(.hidden)
                }
            }

            if history.isEmpty && allTags.isEmpty {
                Text("输入关键词开始搜索,支持中文、拼音与首字母")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func chipsRow(items: [String], removable: Bool,
                          onTap: @escaping (String) -> Void,
                          onRemove: @escaping (String) -> Void = { _ in }) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 4) {
                        Button(item) { onTap(item) }
                            .font(.system(size: 13))
                        if removable {
                            Button {
                                onRemove(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 筛选条(DESIGN 6.3:状态/类型/标签/时间,AND 组合)

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("全部状态") { filter.status = nil; runSearch() }
                    ForEach(IdeaStatus.allCases, id: \.self) { s in
                        Button(s.displayName) { filter.status = s; runSearch() }
                    }
                } label: {
                    filterChip(icon: "circle.grid.cross", text: filter.status?.displayName ?? "状态",
                               active: filter.status != nil)
                }

                Menu {
                    Button("全部类型") { filter.kinds = []; runSearch() }
                    ForEach([AttachmentKind.image, .audio, .link, .file, .video], id: \.self) { k in
                        let label = kindName(k)
                        let on = filter.kinds.contains(k)
                        Button(on ? "✓ \(label)" : label) {
                            if on { filter.kinds.remove(k) } else { filter.kinds.insert(k) }
                            runSearch()
                        }
                    }
                } label: {
                    filterChip(icon: "doc.on.doc", text: filter.kinds.isEmpty ? "类型"
                               : filter.kinds.map(kindName).joined(separator: "·"),
                               active: !filter.kinds.isEmpty)
                }

                Menu {
                    Button("全部标签") { filter.tagNames = []; runSearch() }
                    ForEach(allTags, id: \.objectID) { tag in
                        let on = filter.tagNames.contains(tag.name)
                        Button(on ? "✓ #\(tag.name)" : "#\(tag.name)") {
                            if on {
                                filter.tagNames.removeAll { $0 == tag.name }
                            } else {
                                filter.tagNames.append(tag.name)
                            }
                            runSearch()
                        }
                    }
                } label: {
                    filterChip(icon: "tag", text: filter.tagNames.isEmpty ? "标签"
                               : filter.tagNames.map { "#\($0)" }.joined(separator: ""),
                               active: !filter.tagNames.isEmpty)
                }

                Menu {
                    Button("全部时间") { filter.from = nil; filter.to = nil; runSearch() }
                    Button("今天") { setTimeRange(days: 0) }
                    Button("本周") { setTimeRange(days: 7) }
                    Button("本月") { setTimeRange(days: 30) }
                } label: {
                    filterChip(icon: "calendar", text: timeLabel, active: filter.from != nil)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowSeparator(.hidden)
    }

    private func filterChip(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.system(size: 13)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(active ? Color(env.appTint).opacity(0.15) : Color(.tertiarySystemFill)))
        .foregroundStyle(active ? Color(env.appTint) : Color(.label))
    }

    private var timeLabel: String {
        guard let from = filter.from else { return "时间" }
        let days = Date().timeIntervalSince(from) / 86400
        if days <= 1 { return "今天" }
        if days <= 7 { return "本周" }
        return "本月"
    }

    private func setTimeRange(days: Double) {
        filter.from = Calendar.current.startOfDay(for: Date().addingTimeInterval(-days * 86400))
        filter.to = nil
        runSearch()
    }

    private func kindName(_ k: AttachmentKind) -> String {
        switch k {
        case .image: return "图片"
        case .audio: return "语音"
        case .video: return "视频"
        case .file: return "文件"
        case .link: return "链接"
        }
    }

    // MARK: - 结果

    @ViewBuilder
    private var resultsSection: some View {
        if !searched {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowSeparator(.hidden)
        } else if hits.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text("无结果,试试放宽筛选")
                    .font(.system(size: 15, weight: .medium))
                Button("清除筛选") {
                    filter = SearchFilter()
                    runSearch()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
            .listRowSeparator(.hidden)
        } else {
            HStack {
                Text("\(hits.count) 条结果").font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Picker("排序", selection: $sortByTime) {
                    Text("相关度").tag(false)
                    Text("时间").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: sortByTime) { _, _ in resort() }
            }
            .listRowSeparator(.hidden)

            ForEach(hits, id: \.idea.objectID) { hit in
                NavigationLink {
                    DetailView(idea: hit.idea)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(hit.idea.status.swiftUIColor).frame(width: 6, height: 6)
                            Text(hit.idea.status.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(hit.idea.status.swiftUIColor)
                            Spacer()
                            Text(RelativeTime.string(from: hit.idea.createdAt))
                                .font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        Text(hit.idea.displayTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(highlighted(hit.snippet, keyword: query))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search_result_\(hit.idea.id.uuidString)")
            }
        }
    }

    /// 关键词高亮
    private func highlighted(_ text: String, keyword raw: String) -> AttributedString {
        var attr = AttributedString(text)
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return attr }
        while let range = attr.range(of: keyword, options: .caseInsensitive) {
            attr[range].foregroundColor = Color(env.appTint)
            attr[range].font = .system(size: 13, weight: .semibold)
            break
        }
        return attr
    }

    // MARK: - 防抖搜索(DESIGN 6.3:250ms)

    private func scheduleSearch(_ text: String, immediate: Bool = false) {
        searchTask?.cancel()
        guard immediate || !text.isEmpty else {
            searched = false
            return
        }
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled else { return }
            runSearch()
        }
    }

    private func runSearch() {
        let q = query
        let f = filter
        env.searchService.flushIndex()
        hits = (try? env.searchService.search(query: q, filter: f)) ?? []
        searched = true
        resort()
        // 历史延迟 1.5s 落笔:输入中间前缀不污染历史(终审 #10)
        historyTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        historyTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            env.searchService.recordHistory(trimmed)
        }
    }

    private func resort() {
        if sortByTime {
            hits.sort { $0.idea.createdAt > $1.idea.createdAt }
        }
        // 相关度序 = 服务返回序,无需重排
    }

    private func refreshTags() {
        let req = Tag.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        allTags = (try? env.store.ctx.fetch(req)) ?? []
    }
}
