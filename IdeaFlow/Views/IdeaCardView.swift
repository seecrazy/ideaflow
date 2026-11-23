import SwiftUI

/// 点子卡片(DESIGN 9.1 / 15.3):圆角16 内边距16;状态胶囊=4pt 色条+12pt 文字;
/// 标题 17 Semibold;正文 15;元信息 12;附件徽标;标签 chips。
struct IdeaCardView: View {
    @ObservedObject var idea: Idea
    var isInMultiSelect = false
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !titlePreview.isEmpty {
                Text(titlePreview)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            if let content = contentPreview, !content.isEmpty {
                Text(content)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !idea.tags.isEmpty {
                tagRow
            }
            if !badges.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, image in
                        image
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(alignment: .leading) {
            // 状态色条
            Capsule()
                .fill(idea.status.swiftUIColor)
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 0)
        }
        .opacity(isSelected ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(idea.status.displayName),\(idea.displayTitle)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            if isInMultiSelect {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(envTint) : Color(.tertiaryLabel))
            }
            HStack(spacing: 4) {
                Image(systemName: idea.status.iconName)
                    .font(.system(size: 12))
                Text(idea.status.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(idea.status.swiftUIColor)
            Spacer()
            if idea.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("已置顶")
            }
            Text(RelativeTime.string(from: idea.createdAt))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    // 单向派生,禁止互引(曾因 titlePreview↔contentPreview 互相调用栈溢出白屏)
    private var titlePreview: String {
        if let title = idea.title, !title.isEmpty { return title }
        if let first = idea.content?.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) {
            return String(first.prefix(20))
        }
        return idea.displayTitle
    }

    private var contentPreview: String? {
        guard let content = idea.content else { return nil }
        var lines = content.components(separatedBy: .newlines)
        if idea.title?.isEmpty != false {
            // 首行已借作标题,正文展示其余部分
            if let idx = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                lines.removeFirst(idx + 1)
            }
        }
        let rest = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : String(rest.prefix(140))
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(idea.tags.sorted { $0.name < $1.name }, id: \.objectID) { tag in
                    Text("#\(tag.name)")
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tagColor(tag).opacity(0.15)))
                        .foregroundStyle(tagColor(tag))
                }
            }
        }
    }

    private var badges: [Image] {
        var result: [Image] = []
        let images = idea.attachments.filter { $0.kind == .image }.count
        let audios = idea.attachments.filter { $0.kind == .audio }.count
        let links = idea.attachments.filter { $0.kind == .link }.count
        let files = idea.attachments.filter { $0.kind == .file || $0.kind == .video }.count
        if images > 0 { result.append(Image(systemName: "photo")) }
        if audios > 0 { result.append(Image(systemName: "waveform")) }
        if links > 0 { result.append(Image(systemName: "link")) }
        if files > 0 { result.append(Image(systemName: "doc")) }
        return result
    }

    private func tagColor(_ tag: Tag) -> Color {
        if let hex = tag.colorHex {
            return Color(hexString: hex)
        }
        return Color(envTint)
    }

    private var envTint: UIColor { UIColor(light: 0xE8862E, dark: 0xF09A3E) }
}

extension Color {
    init(hexString: String) {
        var value: UInt64 = 0
        var s = hexString
        if s.hasPrefix("#") { s.removeFirst() }
        Scanner(string: s).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
