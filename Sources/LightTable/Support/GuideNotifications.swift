import Foundation

/// Lets the app-level View menu (in `LightTableApp`) reach the frontmost
/// canvas window without SwiftUI's `@FocusedBinding`/`.focusedSceneValue`
/// machinery — which turned out to carry real per-frame cost once attached
/// to a view (`CanvasView`) that's already re-rendering continuously during
/// a drag. A plain notification only does anything at the moment a menu
/// item is actually clicked, so it has no ongoing cost.
extension Notification.Name {
    static let toggleShowGuides = Notification.Name("LightTable.toggleShowGuides")
    static let openGuideColorPicker = Notification.Name("LightTable.openGuideColorPicker")
    static let clearAllGuides = Notification.Name("LightTable.clearAllGuides")
    static let cropSelected = Notification.Name("LightTable.cropSelected")
    static let deleteSelected = Notification.Name("LightTable.deleteSelected")
    static let duplicateSelected = Notification.Name("LightTable.duplicateSelected")
    static let selectAllItems = Notification.Name("LightTable.selectAllItems")
    static let bulkRename = Notification.Name("LightTable.bulkRename")
    static let refreshAndReflow = Notification.Name("LightTable.refreshAndReflow")
    static let saveDocumentAs = Notification.Name("LightTable.saveDocumentAs")
    static let packageDocument = Notification.Name("LightTable.packageDocument")
    static let deleteFromFolder = Notification.Name("LightTable.deleteFromFolder")
    static let bringForward = Notification.Name("LightTable.bringForward")
    static let bringToFront = Notification.Name("LightTable.bringToFront")
    static let sendBackward = Notification.Name("LightTable.sendBackward")
    static let sendToBack = Notification.Name("LightTable.sendToBack")
    static let createGrid = Notification.Name("LightTable.createGrid")
    static let openBoardSizeDialog = Notification.Name("LightTable.openBoardSizeDialog")
    static let exportPDF = Notification.Name("LightTable.exportPDF")
    static let insertTextField = Notification.Name("LightTable.insertTextField")
    static let insertTextBox = Notification.Name("LightTable.insertTextBox")
}
