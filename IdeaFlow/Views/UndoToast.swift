import SwiftUI
import CoreData

/// 回收站提示条数据:删除即刻可见的反馈 + 可撤销
struct RecycleToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let objectIDs: [NSManagedObjectID]

    static func == (lhs: RecycleToast, rhs: RecycleToast) -> Bool { lhs.id == rhs.id }
}

/// 底部"已删除·可撤销"提示条(邮件式反馈):6 秒自动消失。
/// 根 overlay 挂载处拿不到隐式 environmentObject(App 级注入不覆盖根 overlay),
/// 因此 env 显式传入——LockScreenView 同理。
struct UndoToastView: View {
    let env: AppEnvironment
    let toast: RecycleToast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.circle.fill")
                .foregroundStyle(Color(env.appTint))
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                undo()
            } label: {
                Text("撤销")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(Color(env.appTint))
            .accessibilityIdentifier("undo_button")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(.thickMaterial)
                .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)   // 保留子元素(撤销按钮)可访问
        .accessibilityIdentifier("undo_toast")
        .task(id: toast.id) {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled, env.recycleToast?.id == toast.id {
                env.recycleToast = nil
            }
        }
    }

    private func undo() {
        for oid in toast.objectIDs {
            if let idea = try? env.store.ctx.existingObject(with: oid) as? Idea {
                try? env.store.restore(idea)
            }
        }
        env.recycleToast = nil
    }
}
