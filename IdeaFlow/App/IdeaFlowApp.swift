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
                .overlay {
                    if env.appLock.isLocked {
                        LockScreenView()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    env.appLock.handleScenePhase(phase)
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
    @State private var selection = RootTabView.initialTab()

    static func initialTab() -> Int {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-openPageSearch") { return 1 }
        if args.contains("-openPageTags") { return 2 }
        if args.contains("-openPageSettings") { return 3 }
        return 0
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView() }
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)
            NavigationStack { SearchView() }
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(1)
            NavigationStack { TagsView() }
                .tabItem { Label("标签", systemImage: "tag") }
                .tag(2)
            NavigationStack { SettingsView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppEnvironment(persistence: .preview()))
}

/// Face ID 锁屏遮罩
struct LockScreenView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 46))
                .foregroundStyle(.tertiary)
            Text("灵感集已锁定").font(.headline)
            Button("解锁") {
                Task { await env.appLock.authenticate() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
