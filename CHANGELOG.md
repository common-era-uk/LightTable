# Changelog

All notable changes to LightTable are tracked here, most recent first.

## 1.1.0 — 2026-08-28

- Added art boards: a canvas can now hold multiple boards, stacked vertically, each with its own images and layout. Add one with the "+" button below the last board; right-click a board's background for "Move to…" (type a target position) or "Delete Art Board" (files stay in the folder, same as Remove from Canvas). Drag a card past a board's edge and it lands on whichever board it's now over.
- Added "Board Size…" (toolbar and File menu) to choose between **Auto** — each board sizes itself to fit its own content, the original single-canvas behavior — and **Fixed**, where every board shares one size (inches, cm, or pixels) and never resizes itself; content that no longer fits simply sits past the edge on screen until it's clipped at PDF export, like a real print page. Includes common presets (US Letter, A4, A3, Instagram Post/Story, and a 10×10 in square).
- Added File > "Export as PDF…" — pick which art boards to include and a resolution (dpi), and each becomes one page, in order.
- Opening an existing single-canvas `.lt` file automatically becomes a one-board document (Board 1), sized to whichever is larger of its old canvas size or its actual content — nothing already on the canvas gets clipped.
- Fixed dragging a card back up across a board boundary (e.g. from board 2 to board 1) sometimes being blocked at the boundary instead of crossing it.
- Added a "1920×1080 px (HD)" preset to Board Size.
- Fixed switching board size mode from Fixed back to Auto and then back to Fixed again collapsing the view down to a single board — every board actually survived, but shared a duplicate identity that made SwiftUI display only one.
- Fixed right-clicking a board and choosing "Move to…"/"Delete Art Board" sometimes acting on a different board than the one that was clicked — replaced the per-board right-click menu with a single shared one that tracks the board actually under the cursor.
- Fixed "Export as PDF…" producing correctly-counted but entirely blank pages — the PDF context's own default page size was zero, silently overriding every page's actual size.
- Fixed a Fixed-size board auto-extending anyway when an image was dragged past its edge — Fixed boards now stay locked to exactly their configured size.
- "Save Whole Canvas…" now offers a choice when there's more than one art board — save a single board, or every board at once as separate files — instead of always flattening the whole stack into one image.
- Cards and the crop box now snap to their board's own edges during move/resize, the same way they already snap to guides.
- Added text fields and text boxes — toolbar's "Add Text Field"/"Add Text Box" (also in Edit menu, at the bottom) drop one in, opening a formatting sheet with a live-formatted editor: typeface and size via the system Font panel, Bold/Italic, alignment, colour, letter spacing, and line height. A field doesn't wrap (only an explicit Return breaks a line); a box wraps to its width like a paragraph. Text items behave like image cards in every other way — draggable, same right-click menu, same layering/z-index, same undo — except a plain drag reshapes a text item's box freely (independent width/height), while holding ⌘ or ⌥ scales it proportionally, font size included. Text items don't participate in Create Grid or any file-based operation (rename, refresh from disk, etc.), since they have no file on disk.
- PDF export resolution is now a dropdown (72/96/150/300 dpi) instead of a free-typed number.
- Added standard Cut/Copy/Paste back to the Edit menu (⌘X/⌘C/⌘V) — needed for editing text field/box content; they'd been removed earlier since the canvas itself had no clipboard use for them.
- Reorganized the File menu: New Window, Open…, Open Recent, Set Art Board Size…, Save As…, Export as PDF…, Package…, Bulk Rename…, Close, Close All, in that order.
- Added per-board background colours — right-click a board's background for "Board Colour…" to set just that one board. The toolbar's "Canvas Colour" button now sets the shared default that a board without its own colour falls back to, instead of one color for the whole canvas.
- Changed "color" to "colour" throughout the app's UI text (UK English).

## 1.0.10 — 2026-08-27

- Added "Create Grid" — select two or more images and click the toolbar's Create Grid button (SF icon, before Duplicate) or use View > "Create Grid…" to arrange them into a clean grid with configurable spacing (points or percentage). Images already sitting in a rough row are kept together; rows only merge or split where the canvas width actually requires it, and all images are resized to a shared height. The View menu item is disabled unless 2+ images are selected.
- Added View > "Clear All Guides", right after "Change Guide Color…", to remove every guide from the canvas in one step.
- Reduced the canvas's auto-extend margin (the space it grows beyond your content) by 20%, from 200pt to 160pt.
- Added keyboard shortcuts to the Edit menu: Crop (⇧⌘C), Remove from Canvas (Delete), and Delete from Folder (⌘Delete).
- Moved the "Layer images" tip and added a new "Create Grid" tip to the About screen's Details section.
- Create Grid now defaults to Percentage spacing (20%) instead of Points, and Percentage is listed first.
- Fixed "Copy and Rename in a Different Folder…" opening its folder picker wherever it was last left, instead of at the canvas's own folder.
- Added a "Custom…" aspect ratio option to the crop tool — enter any width:height ratio in two small fields, and it behaves like the built-in presets (draggable, flippable with Rotate).
- Added a "3:4" preset to the crop tool, between "4:5" and "5:7".
- Fixed the crop tool's window being too narrow for vertical images, truncating the aspect preset row; it now has a fixed minimum width so all presets always fit on one line.
- Added the missing keyboard shortcuts to the image card right-click menu — Crop (⇧⌘C), Duplicate (⌘D), Remove from Canvas (Delete), Delete from Folder (⌘Delete) — matching the Edit menu.
- Hold ⌥ (Option) while dragging a corner handle to scale an image card, or the crop box, from its center instead of from the opposite corner.
- Scaling multiple selected cards together (⌘-drag a corner) now scales the whole selection as one rigid block from a shared anchor point, so gaps between cards scale proportionally instead of each card drifting independently and potentially overlapping.
- Added "Apply crops before renaming" to the rename panel — images with a saved crop get the crop baked into their pixels as part of renaming. With "Copy and Rename in a Different Folder…" this only affects the new copies; with "Rename Original Files" it replaces the original's pixels (the untouched original is moved to Trash first, so it stays recoverable).
- Changed the rename panel's defaults: separator "-", start at 1, 2 digits.
- Right-clicking a card that's part of a multi-selection now shows "Create Grid…" as the first menu item, with a divider after it.

## 1.0.9 — 2026-08-22

- Added image layering: Edit > "Bring Forward" (⌘]), "Bring to Front" (⇧⌘]), "Send Backward" (⌘[), and "Send to Back" (⇧⌘[) reorder the selected image(s) above or below the cards around them.
- Added a right-click menu on image cards: Crop, Duplicate, Remove from Canvas, Delete from Folder, and the four layering commands. Right-clicking a card that isn't already selected acts on just that card; right-clicking a card that's part of a multi-selection acts on the whole selection.
- Reworked the Edit menu: Select All now sits above Duplicate; "Delete" is split into "Remove from Canvas" (keeps the file, same as before) and a new "Delete from Folder" (moves the file to Trash, same as the old ⌘-Delete); Cut/Copy/Paste (which never did anything) stay removed.
- Reworked the File menu: added "Open…" (⌘O) after New Window, moved "Bulk Rename…" here from the Edit menu (alongside Save As… and Package…), and moved "Close"/"Close All" down to the bottom of the menu instead of sitting right after Open Recent.

## 1.0.8 — 2026-08-21

- Replaced the hidden `.lighttable.json` sidecar with a visible, double-clickable `.lt` canvas file — a real document you can see and rename in Finder, registered so double-clicking one opens LightTable directly at that canvas.
- A folder can now hold more than one `.lt` canvas. Opening a folder with exactly one canvas opens it directly as before; a folder with several prompts you to choose between them (or create a new one); an empty folder prompts you to name your first canvas.
- Existing folders using the old hidden format are migrated automatically the first time they're opened — you're asked to name the new visible `.lt` file, then the old hidden file is removed.
- Added File > "Save As…" (⇧⌘S) — saves a copy of the current canvas under a new name in the same folder (the images themselves are shared, not duplicated), and switches the window to editing that copy. Useful for trying a different sequence or arrangement of the same images without disturbing the original.
- "Open Recent" now tracks specific canvases rather than folders, so it reopens exactly the one you were last working in.
- Added File > "Package…" — bundles the current canvas (the `.lt` file plus every image it actually uses) into a standalone `.zip`, for sharing outside of whatever's keeping the folder in sync (Dropbox, etc.) between people who already have access to it.

## 1.0.7 — 2026-08-17

- Added a Crop toolbar button (next to Delete) and Edit > Crop — both open the crop tool for the selected image, same as double-clicking it.
- Wired up Edit > Delete to remove the selected image(s) from the canvas, the same as the toolbar Delete button or the Delete key.
- Added a Duplicate feature: the toolbar's Duplicate button (before Crop) or Edit > Duplicate (⌘D) copies the selected image(s) as new "-copy" (then "-copy-2", etc.) files added right next to the originals — handy for trying a few different crops of the same image.
- Added "Copy and Rename in a Different Folder…" to the rename panel — copies files under their planned new names into a folder you choose, instead of renaming the originals in place.
- Cleaned up the Edit menu: removed Cut/Copy/Paste (they never did anything), wired up Select All to select every image on the canvas, and added "Bulk Rename…" to open the rename panel.
- Added View > "Refresh and Reflow", the same action as the toolbar's Refresh button.

## 1.0.6 — 2026-08-09

- Fixed "Toggle Shadows" (originally "Show Shadows") sitting at a deeper indent than the other View menu items — it was a checkbox-style item, and macOS reserves extra indent for every item in the same menu section once one of them can show a checkmark. It's now a plain action, matching "Toggle Guides".
- While previewing, up/down arrow keys now jump a row, landing on whichever image in that row is closest horizontally to the one you're on.
- Holding Space and click-dragging anywhere on the canvas now pans it, the same as a two-finger trackpad swipe.
- Fixed "Toggle Shadows" and "Shadow Settings…" still showing indented in the View menu — they were sharing an unbroken run with the system's own "Enter Full Screen" item right after them, which has an icon; AppKit reserves icon space for every item in a shared run. Added a divider to close off the run, above "Enter Full Screen".
- Added View > "Large Preview Background Settings…" to set the color and opacity behind a large image preview (Space), next to the Shadow options.
- Large Preview Background Settings now also has a "Show filename" toggle and a filename color picker for the label shown under a large preview.
- Redesigned the About screen: a left-hand sidebar ("Getting Started", "Details", "Exporting") now switches between sections with a fade, instead of one long three-column list. Sidebar titles turn black on hover and while active, dark grey otherwise. Added a "View Changelog" link under the credit line that swaps the content area for a scrollable, live copy of this changelog. "Pan the canvas" and "Pan with Space" are now one combined tip.
- Fixed the About screen's window bobbing up and down when switching sections — its content area now has a fixed height and scrolls internally, so the window itself never resizes to fit whatever text happens to be showing.
- Fixed Help > "LightTable Help" saying help wasn't available — it now opens the About screen.
- "Save Visible Area…" and "Save Whole Canvas…" now offer a PNG/JPEG format dropdown in the save panel (updating the filename's extension to match), instead of only picking format from a typed file extension.
- Fixed the format dropdown not responding to clicks — it was a SwiftUI menu-style picker embedded in the save panel, which didn't reliably receive clicks there; rebuilt as a plain native dropdown, the same technique already used for the canvas/guide color pickers.
- Space-drag panning now carries on briefly after you let go, decelerating the same way trackpad momentum scrolling does, instead of stopping dead the instant you release the mouse.
- The app is now signed with a real Developer ID and notarized by Apple, so downloading it no longer triggers a Gatekeeper warning.
- Added LightTable > "Check for Updates…" — checks for and installs new versions automatically, without needing to be sent a fresh copy each time.

## 1.0.5 — 2026-08-07

- Changed Delete to remove an image from the canvas without touching its file — the file stays in the folder and is marked so it won't be auto-imported again on the next open/Refresh. Drag it back onto the canvas from Finder to bring it back.
- Added ⌘-Delete for the old behavior: remove from canvas and move the file to Trash.
- Updated the About screen's "Delete an image" instructions to match.
- The window title bar now shows the folder's full path — ⌘-click the title (or right-click the folder icon next to it) to see the path breadcrumb, same as any Finder window. (Not listed on the About screen — it's standard macOS behavior.)
- Changed the "Rename All…" toolbar icon from "textformat" to "r.square.on.square", freeing up the text-formatting icon in case a future feature adds text to the canvas.
- Added ruler guides: drag a blue guide line in from the canvas's top or left edge, select/reposition it by clicking or dragging, and remove it by dragging it back to the edge or pressing Delete while selected. Images snap to nearby guides when moved or resized (resize snaps whichever dimension — width or height — is closer). Guides are saved per folder and are full undo steps.
- Added a "Guides" toolbar button (left of Filenames) to show/hide guides and their ruler strips, plus matching View menu items: "Toggle Guides" (same toggle, for the frontmost window) and "Change Guide Color…" (opens a color picker just for guides, separate from the canvas background color).
- Reworked guide rendering (`GuideLinesLayer`/`RulerZones`) and the View menu's guide commands to fix dragging/resizing feeling delayed and jerky after guides were added:
  - Guide lines and the ruler strips no longer live directly inside the canvas view, so they're not tied to the same observed object that changes continuously during a card drag.
  - The View menu's guide commands no longer use SwiftUI's `@FocusedBinding`/`.focusedSceneValue`, which carried real per-frame cost once attached to the canvas view — replaced with a lighter notification-based approach that only does anything when a menu item is actually clicked. "Toggle Guides" in the View menu is now a plain action rather than a live checkbox, as a result.
  - An initial attempt also added a `.equatable()` fast-path to skip rebuilding the guide layer when nothing guide-related changed; this was rolled back after it caused guide creation/positioning/snapping bugs (ruler drags jumping to the wrong position, some guides not rendering, snap not working) that weren't worth the extra performance.
- Widened the About screen and split its instructions into three columns instead of two, since the list had grown long enough to need it again.
- Fixed the Guides and Filenames toolbar buttons visibly popping — enlarging and looking pixelated for a moment before shrinking back — every time they were toggled on. They switched between two different button styles (`.bordered`/`.borderedProminent`) in an if/else, which SwiftUI treated as swapping in a whole new button rather than updating the existing one. Both now stay one continuous button, styled the same as every other plain toolbar button, with a circular background (matching the other buttons' own round hover highlight) applied while active.
- Guides now also snap to nearby image edges — both while being dragged in from the ruler and while repositioning an already-placed guide — not just to other guides.
- Added View > "Show Shadows" (toggles image card drop shadows on/off) and View > "Shadow Settings…" (adjusts distance, angle, blur, and opacity), separated from the Guides options by a divider. Unlike canvas/guide color, this applies app-wide across every folder rather than being saved per canvas, and is remembered across launches.
- Arrow keys now nudge the selected image(s) by 1pt — hold Shift for 10pt. Each nudge is its own undo step.
- Added a large image preview: select a single image and press Space to see it big, like Quick Look — Space, Escape, or a click closes it again. While previewing, left/right arrow keys step to the next/previous image in the canvas's reading order, wrapping onto the next or previous row at the end of a row.

## 1.0.4 — 2026-08-06

- Added a canvas color picker in the toolbar (after the Filenames button) to set a custom canvas background color, persisted per folder. Exports ("Save Visible Area" / "Save Whole Canvas") use it too when set.
- Changed the canvas color button from a large swatch mirroring the current color to a native palette icon.
- Added Canvas Color and Undo/Refresh to the About screen's instructions.
- Added left padding in the toolbar so the zoom percentage isn't flush against the edge.

## 1.0.3 — 2026-08-01

- Added a Filenames toggle in the toolbar — shows each image's filename in a small badge below its card.
- Added ⌘-group-scale: with 2+ cards selected, holding ⌘ while dragging any card's corner handle scales every other selected card by the same proportion, each from its own matching corner.
- Fixed the blank "open a folder" window/tab lingering after opening a folder some other way (toolbar button, Open Recent, Dock drop) — it now closes itself automatically. Native tab support is unchanged; folders still open as tabs as before.

## 1.0.2 — 2026-07-27

- Added Undo (⌘Z, up to 10 levels), covering move, resize, crop, delete, drag-drop import, refresh, and canvas resize. Undo reverses the actual file operation too (e.g. restores a deleted file from Trash), not just the on-screen position.
- Added a Refresh button (next to the export buttons) that re-reads the folder from disk and re-flows all images into a fresh grid, resizing the canvas to fit — handy for regrouping after deleting a batch of images.
- Added a size guard: opening a folder or dragging in a file over 150 MB is rejected with a clear message instead of risking a crash from decoding a huge image.
- Added File > Open Recent, listing the last 10 opened folders.

## 1.0.1 — 2026-07-27

- Fixed image renames losing their canvas position/size/crop — files are now tracked by a stable file ID that survives renames, not just by filename.
- Fixed the canvas's bottom edge not being draggable to resize.
- Cards can no longer be dragged, resized, or dropped off the left/top edges of the canvas (right/bottom still auto-extend).
- Crop dialog: you can now drag inside the crop box to move it, not just drag the corner handles.
- Crop dialog: guide lines and corner handles are now blue (accent color) instead of white, and the cursor changes to a resize arrow when hovering a corner.
- Crop dialog: instruction text no longer gets cut off, and explains "Apply" vs "Apply & Export".
- "Open Folder…" now opens the chosen folder in a new window instead of replacing the current one.

## 1.0.0 — 2026-07-27

- First versioned release.
- Added an About LightTable screen with usage instructions (opening a folder, panning, zooming, moving/resizing, cropping, deleting, renaming, exporting).
- Added "Apply & Export" in the crop dialog — saves a cropped copy of the file (named with a "-crop" suffix) alongside the original, which stays untouched.
- Added a credit line ("Created by Kevin Moore").

## Earlier (0.1.0 and before)

Initial build: folder-bound canvas, drag/resize/crop/delete/bulk-rename, marquee multi-select, pan/zoom, canvas export, custom app icon, Dock-drop-to-open, and packaging as a standalone .app.
