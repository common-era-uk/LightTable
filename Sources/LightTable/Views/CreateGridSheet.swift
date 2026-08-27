import SwiftUI

struct CreateGridSheet: View {
    let onCreate: (Double, Bool) -> Void
    let onCancel: () -> Void

    private enum SpacingUnit: String, CaseIterable {
        case percentage = "Percentage"
        case points = "Points"
    }

    @State private var spacingValue: Double = 20
    @State private var unit: SpacingUnit = .percentage

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
                Text(unit == .points ? "pt" : "% of image height")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Grid") {
                    onCreate(max(spacingValue, 0), unit == .percentage)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
