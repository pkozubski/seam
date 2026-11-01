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

window-desktop-mac.png / window-desktop-pc.png: original paired emerald/blue
wallpapers generated with built-in image_gen for the Windows tab's monitor diagrams.
window-prompts.txt records both exact prompts. The windows, shared edge, arrows and
localized labels are drawn natively on each platform. All diagrams follow the
configured screen arrangement. Only the Windows app draws these diagrams now; the macOS
Windows page uses the hero-windows-* assets instead.

hero-connection.png, tile-*.png: blue glass hero and feature tiles of the Connection page;
hero-prompts.txt records the prompts.
hero-control-mouse.png, hero-control-key.png, tile-input.png: magenta glass assets of the Keyboard & mouse page.
hero-audio-headphones.png, tile-audio-violet.png: violet glass assets of the Sound page.
hero-clipboard-board.png, hero-clipboard-text.png, hero-clipboard-photo.png, tile-clipboard-amber.png: amber glass assets of the Clipboard page.
hero-windows-laptop.png, hero-windows-monitor.png, hero-windows-window.png, tile-windows-lime.png: leaf-green glass assets of the macOS Windows page.
