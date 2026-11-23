import SwiftUI

/// 详情页(Task 9 实现)
struct DetailView: View {
    @ObservedObject var idea: Idea

    var body: some View {
        Text(idea.displayTitle)
            .navigationTitle("点子详情")
    }
}

/// 搜索页(Task 10 实现)
struct SearchView: View {
    var body: some View {
        Text("搜索")
            .navigationTitle("搜索")
    }
}

/// 标签页(Task 11 实现)
struct TagsView: View {
    var body: some View {
        Text("标签")
            .navigationTitle("标签")
    }
}

/// 设置页(Task 11 实现)
struct SettingsView: View {
    var body: some View {
        Text("我的")
            .navigationTitle("我的")
    }
}

/// 回收站(Task 11 实现)
struct RecycleBinView: View {
    var body: some View {
        Text("回收站")
            .navigationTitle("回收站")
    }
}
