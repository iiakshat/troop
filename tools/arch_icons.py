"""Writes the level-archetype map badges (spec v2.1 §4.1): assets/icons/arch_<id>.svg.
Run from the project root: python -I tools/arch_icons.py
Our own simple vector drawings: a coloured disc with a white glyph, dark rim."""
from pathlib import Path

OUT = Path("assets/icons")

def badge(color: str, glyph: str) -> str:
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 128 128">'
            f'<circle cx="64" cy="64" r="58" fill="#1b1f2a"/>'
            f'<circle cx="64" cy="64" r="52" fill="{color}"/>'
            f'<circle cx="64" cy="58" r="44" fill="#ffffff" fill-opacity="0.13"/>'
            f'<g fill="#ffffff" stroke="#ffffff" stroke-linecap="round" stroke-linejoin="round">{glyph}</g>'
            '</svg>\n')

W = 'fill="none" stroke-width="10"'
ICONS = {
    # the road ahead with one chevron (review v2.1: crossed night-sticks read as the close X)
    "gauntlet": ("#3d6fd6", '<path stroke="none" d="M50 30 L78 30 L94 100 L34 100 Z"/>'
                            '<g fill="#3d6fd6" stroke="none"><rect x="61" y="36" width="6" height="10" rx="2"/>'
                            '<rect x="60" y="84" width="8" height="12" rx="2"/></g>'
                            '<path fill="none" stroke="#3d6fd6" stroke-width="9" d="M47 74 L64 57 L81 74"/>'),
    # double chevrons up the street
    "rush": ("#ff8a1f", f'<path {W} d="M38 70 L64 46 L90 70 M38 92 L64 68 L90 92"/>'),
    # crosshair
    "ambush": ("#e5463b", f'<circle cx="64" cy="64" r="26" {W}/>'
                          f'<path {W} d="M64 22 V40 M64 88 V106 M22 64 H40 M88 64 H106"/>'
                          '<circle cx="64" cy="64" r="7" stroke="none"/>'),
    # crescent moon and a star
    "night": ("#3b3f9e", '<path stroke="none" d="M74 30 A36 36 0 1 0 98 82 A28 28 0 1 1 74 30 Z"/>'
                         '<path stroke="none" d="M86 30 l4 9 l9 1 l-7 6 l2 9 l-8 -5 l-8 5 l2 -9 l-7 -6 l9 -1 Z"/>'),
    # rank insignia: a star over two chevrons
    "lieutenant": ("#8e44ad", '<path stroke="none" d="M64 24 l7 14 l15 2 l-11 10 l3 15 l-14 -7 l-14 7 l3 -15 l-11 -10 l15 -2 Z"/>'
                              f'<path {W} d="M40 78 L64 92 L88 78 M40 96 L64 110 L88 96" stroke-width="9"/>'),
    # a cage with a padlock
    "rescue": ("#2e9e5b", '<rect x="34" y="34" width="60" height="10" rx="4" stroke="none"/>'
                          '<rect x="34" y="88" width="60" height="10" rx="4" stroke="none"/>'
                          '<path fill="none" stroke-width="7" d="M42 44 V88 M56 44 V88 M72 44 V88 M86 44 V88"/>'
                          '<rect x="58" y="62" width="22" height="18" rx="4" fill="#ffc93a" stroke="#1b1f2a" stroke-width="3"/>'
                          '<path fill="none" stroke="#1b1f2a" stroke-width="4" d="M63 62 V56 A6 6 0 0 1 75 56 V62"/>'),
    # a crowd: three heads and shoulders
    "horde": ("#b23a3a", '<circle cx="64" cy="44" r="13" stroke="none"/><path stroke="none" d="M40 92 Q64 54 88 92 Z"/>'
                         '<circle cx="36" cy="56" r="10" stroke="none"/><path stroke="none" d="M18 98 Q36 68 54 98 Z"/>'
                         '<circle cx="92" cy="56" r="10" stroke="none"/><path stroke="none" d="M74 98 Q92 68 110 98 Z"/>'),
    # a cloud with a lightning bolt
    "storm": ("#55667a", '<path stroke="none" d="M40 70 A16 16 0 0 1 42 38 A22 22 0 0 1 84 34 A18 18 0 0 1 92 70 Z"/>'
                         '<path fill="#ffd23f" stroke="#ffd23f" stroke-width="2" d="M66 66 L52 92 H64 L58 112 L80 82 H67 L74 66 Z"/>'),
    # a flame
    "hard": ("#d9381e", '<path stroke="none" d="M64 20 C70 40 92 50 90 78 A26 26 0 0 1 38 78 C36 62 46 54 50 44 C54 56 58 60 62 60 C60 46 60 32 64 20 Z"/>'
                        '<path fill="#ffd23f" stroke="none" d="M64 62 C68 72 78 76 76 88 A12 12 0 0 1 52 88 C52 80 58 76 60 70 C62 74 64 74 64 62 Z"/>'),
}

for name, (color, glyph) in ICONS.items():
    (OUT / f"arch_{name}.svg").write_text(badge(color, glyph), encoding="utf-8", newline="\n")
print("wrote", len(ICONS))
