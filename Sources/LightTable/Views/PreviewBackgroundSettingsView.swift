import SwiftUI

struct PreviewBackgroundSettingsView: View {
    @ObservedObject private var settings = PreviewBackgroundSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Large Preview Background")
                .font(.title2.bold())

            ColorPicker("Background colour", selection: $settings.color, supportsOpacity: false)

            slider("Opacity", value: $settings.opacity, range: 0...1, format: "%.0f%%", displayScale: 100)

            Divider()

            Toggle("Show filename", isOn: $settings.showFilename)

            ColorPicker("Filename colour", selection: $settings.filenameColor, supportsOpacity: false)
                .disabled(!settings.showFilename)
                .opacity(settings.showFilename ? 1 : 0.4)

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
