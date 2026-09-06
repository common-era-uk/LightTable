# Changelog

What's changed in LightTable, most recent first. Written in plain terms, not developer notes.

## 1.1.3 — 2026-09-07

- Create Grid now has a "Max Per Row" or "Max Per Column" option, to force an exact count along one axis instead of fitting the canvas width.

## 1.1.2 — 2026-09-04

- Text editing is now fully inline — double-click a text item to type directly on the canvas, with a small floating panel for typeface, size, Bold/Italic, colour, alignment, letter spacing and line height.
- Added a Justify text alignment option.
- The "overset" badge (content that no longer fits its frame) now also applies to text fields, not just text boxes.

## 1.1.1 — 2026-09-02

- Dropping multiple files from Finder now cascades them diagonally instead of stacking them on top of each other.
- Dragging a file from Finder onto an existing image card now replaces its content in place.
- Fixed replacing an image with a file already used by another card sometimes making one card disappear on reopening.
- Holding Shift while dragging an image or text item now restricts movement to a straight line.
- A text box that no longer fits its content shows a small red "…" badge.
- Cut, Copy and Paste now work on the canvas selection, not just inside text fields.

## 1.1.0 — 2026-08-28

- Added art boards — a canvas can hold multiple boards, each with its own images and layout.
- Added Board Size: Auto (each board fits its content) or Fixed (a shared size, like a real print page).
- Added Export as PDF — choose which art boards to include and a resolution; each becomes a page.
- Opening an old single-canvas file now becomes a one-board document automatically.
- Several fixes to art board dragging, resizing and right-click behaviour.
- Added text fields and text boxes, with their own formatting panel (typeface, size, Bold/Italic, alignment, colour, spacing).
- Added per-board background colours.
- Added Cut/Copy/Paste back to the Edit menu, for text content.
- Reorganised the File menu.
- Changed "color" to "colour" throughout (UK English).

## 1.0.10 — 2026-08-27

- Added Create Grid — arrange selected images into a clean, evenly spaced grid.
- Added "Clear All Guides" to remove every guide in one step.
- Added keyboard shortcuts for Crop, Remove from Canvas and Delete from Folder.
- Added a Custom aspect ratio option and a 3:4 preset to the crop tool.
- Fixed the crop tool window being too narrow for vertical images.
- Added Option-drag to scale an image or crop box from its centre.
- Scaling multiple selected images together now scales them as one block.
- Added "Apply crops before renaming" to the rename panel.

## 1.0.9 — 2026-08-22

- Added image layering: Bring Forward/to Front, Send Backward/to Back.
- Added a right-click menu on image cards (Crop, Duplicate, Remove, Delete, layering).
- Reworked the Edit and File menus for clarity.

## 1.0.8 — 2026-08-21

- Replaced the hidden canvas file with a visible, double-clickable `.lt` file.
- A folder can now hold more than one canvas.
- Added Save As…, to save a copy of the current canvas under a new name.
- Open Recent now reopens the exact canvas you were last working in.
- Added Package…, to bundle a canvas and its images into a shareable zip.

## 1.0.7 — 2026-08-17

- Added a Crop toolbar button and Edit ▸ Crop.
- Added Duplicate, to copy selected images as new files alongside the originals.
- Added "Copy and Rename in a Different Folder…" to the rename panel.
- Cleaned up the Edit menu.

## 1.0.6 — 2026-08-09

- Arrow keys now jump a row while previewing an image.
- Holding Space and dragging now pans the canvas.
- Added background and filename settings for the large image preview.
- Redesigned the About screen with a sidebar and a live changelog link.
- Save panels now offer a PNG/JPEG format dropdown.
- Space-drag panning now decelerates smoothly instead of stopping dead.
- The app is now signed and notarised, so it opens without a Gatekeeper warning.
- Added Check for Updates, so new versions install automatically.

## 1.0.5 — 2026-08-07

- Delete now removes an image from the canvas without touching its file; ⌘-Delete does the old full delete (moves it to Trash).
- The window title bar now shows the folder's full path.
- Added ruler guides, with snapping, per-folder colour and full undo support.
- Added a Guides toolbar button and View menu options.
- Fixed dragging/resizing feeling delayed and jerky after guides were added.
- Guides now also snap to image edges, not just other guides.
- Added Show Shadows and Shadow Settings for image card drop shadows.
- Arrow keys now nudge the selected image(s); Shift for a bigger step.
- Added a large image preview (press Space), with arrow-key navigation between images.

## 1.0.4 — 2026-08-06

- Added a canvas colour picker, remembered per folder and used in exports.
- Small toolbar polish.

## 1.0.3 — 2026-08-01

- Added a Filenames toggle, showing each image's filename below its card.
- Added ⌘-group-scale, to resize multiple selected cards together proportionally.
- Fixed a blank window sometimes lingering after opening a folder.

## 1.0.2 — 2026-07-27

- Added Undo (⌘Z, up to 10 levels), covering move, resize, crop, delete, import and refresh.
- Added a Refresh button to re-read the folder and re-flow the canvas.
- Added a size guard against very large files.
- Added Open Recent, listing the last 10 folders.

## 1.0.1 — 2026-07-27

- Fixed image renames losing their canvas position, size and crop.
- Fixed the canvas's bottom edge not being resizable.
- Several crop dialog improvements (drag to move, clearer instructions, colour).
- Open Folder now opens in a new window instead of replacing the current one.

## 1.0.0 — 2026-07-27

- First versioned release.
- Added an About screen with usage instructions.
- Added "Apply & Export" in the crop dialog.
- Added a credit line.

## Earlier (0.1.0 and before)

Initial build: folder-bound canvas, drag/resize/crop/delete/bulk-rename, marquee multi-select, pan/zoom, canvas export, custom app icon, Dock-drop-to-open, and packaging as a standalone app.
