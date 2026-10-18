#!/usr/bin/env python3
"""Eksportuje wspólną ikonę BorderlessMouse dla macOS i Windows.

Źródło: assets/logo/app-icon.png (kwadrat z kanałem alfa, kafelek na środku).
Podmień ten plik, a następnie uruchom:
    python3 assets/logo/generate_logo.py
Wymaga Pillow.
"""
from pathlib import Path

from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent
SOURCE = OUT / "app-icon.png"
CANVAS = 1024
# Siatka ikon macOS: kafelek 824 × 824 na płótnie 1024 × 1024.
MAC_TILE = 824
# Windows i README: kafelek prawie na całe płótno, z cienkim marginesem.
FULL_TILE = 984
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
ICNS_SIZES = (32, 64, 128, 256, 512, 1024)


def render(source, size):
    """Skaluje gotową grafikę, zachowując jej kompozycję i tło."""
    return source.resize((size, size), Image.Resampling.LANCZOS)


def tile_bounds(source):
    """Zwraca prostokąt kafelka, pomijając półprzezroczyste krawędzie."""
    opaque = source.getchannel("A").point(lambda alpha: 255 if alpha > 200 else 0)
    bounds = opaque.getbbox()
    if bounds is None:
        raise ValueError(f"Ikona źródłowa nie ma nieprzezroczystego kafelka: {SOURCE}")
    return bounds


def fit_tile(source, tile_size):
    """Wycina kafelek i centruje go na przezroczystym płótnie CANVAS."""
    tile = source.crop(tile_bounds(source))
    scale = tile_size / max(tile.size)
    tile = tile.resize(
        (round(tile.width * scale), round(tile.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (CANVAS, CANVAS))
    canvas.alpha_composite(tile, ((CANVAS - tile.width) // 2, (CANVAS - tile.height) // 2))
    return canvas


def add_shadow(icon, offset=10, blur=12, opacity=0.3):
    """Dodaje delikatny cień pod kafelkiem, jak w ikonach systemowych macOS."""
    alpha = icon.getchannel("A").point(lambda value: round(value * opacity))
    shadow = Image.new("RGBA", icon.size)
    shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(blur)))
    result = Image.new("RGBA", icon.size)
    result.alpha_composite(shadow, (0, offset))
    result.alpha_composite(icon)
    return result


def write_ico(source, path):
    source.save(path, format="ICO", sizes=[(size, size) for size in ICO_SIZES])


def write_icns(source, path):
    # Pillow zapisuje bezstratne reprezentacje PNG, w tym warianty Retina.
    source.save(
        path,
        format="ICNS",
        append_images=[render(source, size) for size in ICNS_SIZES],
    )


def main():
    with Image.open(SOURCE) as image:
        if image.width != image.height or image.width < CANVAS:
            raise ValueError(f"Ikona źródłowa musi być kwadratem ≥ {CANVAS} px: {SOURCE}")
        source = image.convert("RGBA")

    full = fit_tile(source, FULL_TILE)
    full.save(OUT / "logo-1024.png")
    render(full, 256).save(OUT / "logo-256.png")

    win_assets = ROOT / "windows" / "BorderlessMouse" / "Assets"
    render(full, 256).save(win_assets / "icon.png")
    render(full, 512).save(win_assets / "logo.png")
    write_ico(full, win_assets / "icon.ico")

    write_icns(
        add_shadow(fit_tile(source, MAC_TILE)),
        ROOT / "macos" / "BorderlessMouse" / "Resources" / "AppIcon.icns",
    )
    print("Ikony PNG, ICO i ICNS zostały wyeksportowane z app-icon.png.")


if __name__ == "__main__":
    main()
