import SwiftUI

struct ShadowSettingsView: View {
    @ObservedObject private var settings = ShadowSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shadow Settings")
                .font(.title2.bold())

            Toggle("Show shadows", isOn: $settings.enabled)

            VStack(alignment: .leading, spacing: 16) {
                slider("Distance", value: $settings.distance, range: 0...20, format: "%.0f pt")
                slider("Angle", value: $settings.angle, range: 0...360, format: "%.0f°")
                slider("Blur", value: $settings.blur, range: 0...12, format: "%.0f pt")
                slider("Opacity", value: $settings.opacity, range: 0...1, format: "%.0f%%", displayScale: 100)
            }
            .disabled(!settings.enabled)
            .opacity(settings.enabled ? 1 : 0.4)

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .padding(28)
        .frame(width: 340)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, displayScale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * displayScale))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: value, in: range)
        }
    }
}
