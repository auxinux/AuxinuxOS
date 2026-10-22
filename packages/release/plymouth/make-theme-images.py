#!/usr/bin/env python3
"""Genere les images du theme Plymouth auxinux (logo + arc orange).

Les PNG produits sont versionnes dans packages/release/root/usr/share/plymouth/
themes/auxinux/: ce script ne sert qu'a les refaire si le logo change.

    python3 packages/release/plymouth/make-theme-images.py

Couleurs communes avec AuxiNux Shell (ecran d'ouverture de session): fond
#151b23, accent #ef8a12 (palette « auxinux » du Shell et du centre).
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
LOGO = ROOT / "image-builder/assets/logo-AuxiNux-square.png"
OUT = ROOT / "packages/release/root/usr/share/plymouth/themes/auxinux"

ACCENT = (0xEF, 0x8A, 0x12)
TRACK = (0xFF, 0xFF, 0xFF, 0x22)
SS = 4  # sur-echantillonnage pour des bords lisses


def logo(size: int) -> None:
    img = Image.open(LOGO).convert("RGBA")
    # Le carre est surtout transparent: on garde le mot-symbole seul.
    img = img.crop(img.getbbox())
    img.thumbnail((size, size), Image.LANCZOS)
    img.save(OUT / "logo.png", optimize=True)


def spinner(size: int, width: int) -> None:
    """Arc de 270 degres qui s'estompe vers la queue, sur une piste discrete.

    Plymouth le fait tourner (Image.Rotate dans auxinux.script)."""
    big = size * SS
    w = width * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    box = (w // 2, w // 2, big - w // 2 - 1, big - w // 2 - 1)
    d.arc(box, 0, 360, fill=TRACK, width=w)
    steps = 90
    for i in range(steps):
        a0 = -90 + i * 270 / steps
        alpha = int(40 + 215 * ((i + 1) / steps) ** 0.8)
        d.arc(box, a0, a0 + 270 / steps + 1, fill=ACCENT + (alpha,), width=w)
    img = img.resize((size, size), Image.LANCZOS)
    img.save(OUT / "spinner.png", optimize=True)


def entry_box() -> None:
    """Champ de mot de passe (secours LUKS) et puce de caractere."""
    w, h = 320, 40
    big = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rounded_rectangle((0, 0, w * SS - 1, h * SS - 1), radius=8 * SS,
                        fill=(0x0B, 0x10, 0x16, 0xFF), outline=ACCENT + (0xFF,), width=2 * SS)
    big.resize((w, h), Image.LANCZOS).save(OUT / "entry.png", optimize=True)
    b = 10
    big = Image.new("RGBA", (b * SS, b * SS), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse((0, 0, b * SS - 1, b * SS - 1), fill=(0xFF, 0xFF, 0xFF, 0xFF))
    big.resize((b, b), Image.LANCZOS).save(OUT / "bullet.png", optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    logo(360)
    spinner(56, 5)
    entry_box()
    print(f"images ecrites dans {OUT}")
