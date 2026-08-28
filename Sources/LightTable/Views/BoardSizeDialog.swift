import SwiftUI

struct BoardSizeDialog: View {
    @ObservedObject var document: CanvasDocument
    @Binding var isPresented: Bool

    @State private var mode: BoardSizeMode
    @State private var unit: BoardSizeUnit
    @State private var widthValue: Double
    @State private var heightValue: Double

    init(document: CanvasDocument, isPresented: Binding<Bool>) {
        self.document = document
        self._isPresented = isPresented
        _mode = State(initialValue: document.boardSizeMode)
        let unit = document.boardSizeUnit
        _unit = State(initialValue: unit)
        _widthValue = State(initialValue: unit.value(fromPoints: document.fixedBoardWidth))
        _heightValue = State(initialValue: unit.value(fromPoints: document.fixedBoardHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Board Size")
                .font(.title2.bold())
            Text("Auto lets each art board size itself to fit its own content, the same way the canvas already works. Fixed locks every board to one size — content that no longer fits simply sits past the edge on screen, and is clipped only at PDF export, like a real print page.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $mode) {
                Text("Auto").tag(BoardSizeMode.auto)
                Text("Fixed").tag(BoardSizeMode.fixed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .fixed {
                Picker("Preset", selection: presetBinding) {
                    Text("Custom").tag(Optional<UUID>.none)
                    ForEach(BoardSizePreset.all) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }

                Picker("", selection: $unit) {
                    ForEach(BoardSizeUnit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: unit) { oldUnit, newUnit in
                    // Convert the currently-typed values into the new unit so
                    // switching units doesn't silently change the size.
                    let widthPoints = oldUnit.points(from: widthValue)
                    let heightPoints = oldUnit.points(from: heightValue)
                    widthValue = newUnit.value(fromPoints: widthPoints)
                    heightValue = newUnit.value(fromPoints: heightPoints)
                }

                HStack {
                    TextField("Width", value: $widthValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("×")
                    TextField("Height", value: $heightValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text(unit.label)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    /// Highlights whichever preset (if any) the current width/height
    /// already matches, and lets picking one fill in its values.
    private var presetBinding: Binding<UUID?> {
        Binding(
            get: {
                let widthPoints = unit.points(from: widthValue)
                let heightPoints = unit.points(from: heightValue)
                return BoardSizePreset.all.first { abs($0.width - widthPoints) < 0.5 && abs($0.height - heightPoints) < 0.5 }?.id
            },
            set: { newID in
                guard let preset = BoardSizePreset.all.first(where: { $0.id == newID }) else { return }
                widthValue = unit.value(fromPoints: preset.width)
                heightValue = unit.value(fromPoints: preset.height)
            }
        )
    }

    private func apply() {
        document.setBoardSizeMode(mode)
        if mode == .fixed {
            document.setFixedBoardSize(width: unit.points(from: max(widthValue, 1)), height: unit.points(from: max(heightValue, 1)), unit: unit)
        }
        isPresented = false
    }
}
