seam — shared interface assets

seam-windows.png: generated glass-window illustration, transparent background.
seam-icon.png: generated app icon source, transparent background.
seam.icns / seam.ico: app icon packages derived from that source.
*.svg: editable navigation icon masters, mirrored in Avalonia geometry; macOS uses SF Symbols.
prompts.txt: exact prompts used with built-in image_gen.

macOS build.sh copies these assets into the app bundle. Windows embeds PNGs through linked AvaloniaResource entries. No runtime downloads.

icon-*.png: eight generated silver 3D icons used by both platforms.
icon-prompts.txt: their exact image_gen prompts.
Connection status is displayed in an attached transparent child window, with screen-edge clamping.
