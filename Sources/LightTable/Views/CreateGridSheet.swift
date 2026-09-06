import SwiftUI

struct CreateGridSheet: View {
    let onCreate: (Double, Bool, GridLayoutLimit) -> Void
    let onCancel: () -> Void

    private enum SpacingUnit: String, CaseIterable {
        case percentage = "Percentage"
        case points = "Points"
    }

    private enum LimitMode: String, CaseIterable, Identifiable {
        case fitWidth = "Fit Width"
        case maxPerRow = "Max Per Row"
        case maxPerColumn = "Max Per Column"
        var id: String { rawValue }
    }

    @State private var spacingValue: Double = 20
    @State private var unit: SpacingUnit = .percentage
    @State private var limitMode: LimitMode = .fitWidth
    @State private var maxCount: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Grid")
                .font(.title2.bold())
            Text("Lays out the selected images in a grid — all resized to a shared height, wrapping rows to fit the canvas width.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $unit) {
                ForEach(SpacingUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("Spacing between images:")
                TextField("", value: $spacingValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text(spacingUnitLabel)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker("", selection: $limitMode) {
                ForEach(LimitMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if limitMode != .fitWidth {
                Stepper(value: $maxCount, in: 1...50) {
                    HStack {
                        Text(limitMode == .maxPerRow ? "Images per row:" : "Images per column:")
                        Spacer()
                        Text("\(maxCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Grid") {
                    onCreate(max(spacingValue, 0), unit == .percentage, limit)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    /// The shared dimension spacing is a percentage *of* — image height for
    /// the default and per-row modes (every image shares a height), image
    /// width for per-column (every image shares a width instead).
    private var spacingUnitLabel: String {
        guard unit == .percentage else { return "pt" }
        return limitMode == .maxPerColumn ? "% of image width" : "% of image height"
    }

    private var limit: GridLayoutLimit {
        switch limitMode {
        case .fitWidth: return .fitWidth
        case .maxPerRow: return .maxPerRow(maxCount)
        case .maxPerColumn: return .maxPerColumn(maxCount)
        }
    }
}
