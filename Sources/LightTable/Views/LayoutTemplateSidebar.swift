import SwiftUI

/// The window's left-hand sidebar. For now it holds just the layout
/// templates; clicking one applies it to the current page (see
/// `LayoutTemplateCommands` for how that page is chosen).
struct LayoutTemplateSidebar: View {
    static let width: CGFloat = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Layout Templates")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Click to lay out the selected page — or the one in view — using its existing images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(LayoutTemplate.all) { template in
                    LayoutTemplateTile(template: template)
                }
            }
            .padding(14)
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LayoutTemplateTile: View {
    let template: LayoutTemplate
    @State private var isHovering = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .applyLayoutTemplate, object: template.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                LayoutTemplateThumbnail(template: template)
                    .aspectRatio(LayoutTemplate.pageSize.width / LayoutTemplate.pageSize.height, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(isHovering ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isHovering ? 2 : 1)
                    )
                HStack(spacing: 4) {
                    Text(template.name)
                        .font(.caption)
                    Spacer(minLength: 0)
                    Text(imageCountLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Apply \"\(template.name)\" to the current page")
    }

    private var imageCountLabel: String {
        let count = template.imageSlots.count
        return count == 0 ? "no images" : "\(count) image\(count == 1 ? "" : "s")"
    }
}

/// A wireframe of a template: darker blocks for fill (cropped) slots,
/// lighter ones for fit slots, and bars for text.
private struct LayoutTemplateThumbnail: View {
    let template: LayoutTemplate

    var body: some View {
        Canvas { context, size in
            let scale = size.width / LayoutTemplate.pageSize.width
            func scaled(_ rect: CGRect) -> CGRect {
                CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            }

            let page = CGRect(origin: .zero, size: size)
            context.fill(Path(page), with: .color(template.backgroundColor?.color ?? .white))

            for slot in template.imageSlots {
                let rect = scaled(slot.frame)
                let shade = slot.mode == .fill ? 0.55 : 0.72
                context.fill(Path(rect), with: .color(Color(white: shade)))
            }

            for element in template.texts {
                let rect = scaled(element.frame)
                let barHeight = max(rect.height * 0.45, 2)
                let barWidth = min(rect.width, Double(element.text.count) * element.fontSize * 0.62 * scale)
                let bar = CGRect(x: rect.midX - barWidth / 2, y: rect.midY - barHeight / 2, width: barWidth, height: barHeight)
                context.fill(Path(roundedRect: bar, cornerRadius: barHeight / 2), with: .color(Color(white: 0.25)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
