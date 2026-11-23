import SwiftUI

@main
struct IdeaFlowApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            Text("首页").tabItem { Label("首页", systemImage: "house.fill") }
            Text("搜索").tabItem { Label("搜索", systemImage: "magnifyingglass") }
            Text("标签").tabItem { Label("标签", systemImage: "tag") }
            Text("我的").tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootTabView()
}
