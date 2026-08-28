import SwiftUI

/// Right-click "Move to…" on an art board — types a target position rather
/// than dragging, since a project realistically has a handful of boards.
struct MoveBoardDialog: View {
    let boardIndex: Int
    let boardCount: Int
    let onMove: (Int) -> Void
    let onCancel: () -> Void

    @State private var targetPosition: Int

    init(boardIndex: Int, boardCount: Int, onMove: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.boardIndex = boardIndex
        self.boardCount = boardCount
        self.onMove = onMove
        self.onCancel = onCancel
        _targetPosition = State(initialValue: boardIndex + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move Art Board \(boardIndex + 1)")
                .font(.title2.bold())
            HStack {
                Text("Move to position:")
                Stepper(value: $targetPosition, in: 1...boardCount) {
                    Text("\(targetPosition)")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Move") { onMove(targetPosition - 1) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(targetPosition - 1 == boardIndex)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
