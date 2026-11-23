import SwiftUI

@main
struct IdeaFlowApp: App {
    @StateObject private var env = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(env)
                .tint(Color(env.appTint))
                .onChange(of: scenePhase) { _, phase in
                    // DESIGN §4.3:失焦/退后台立即落草稿,不等 500ms 节流
                    if phase != .active, !env.currentInputText.isEmpty {
                        env.draftService.save(text: env.currentInputText)
                    }
                }
        }
    }
}

extension AppEnvironment {
    /// 品牌主色:暖琥珀,区别于系统蓝的"灵感"气质
    var appTint: UIColor { UIColor(light: 0xE8862E, dark: 0xF09A3E) }
}

struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("首页", systemImage: "house.fill") }
            NavigationStack { SearchView() }
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            NavigationStack { TagsView() }
                .tabItem { Label("标签", systemImage: "tag") }
            NavigationStack { SettingsView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppEnvironment(persistence: .preview()))
}
