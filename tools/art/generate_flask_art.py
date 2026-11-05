"""Writes the vector artwork of the battle flasks to features/battle/art/obstacles/flasks/.

Every flask is drawn from the same shapes so the ten variants share one style; only the
liquid palette and the silhouette differ. Run from the project root:

    python tools/art/generate_flask_art.py

Godot imports the SVG files as textures (see the .import files next to them).
"""

from pathlib import Path

OUTPUT = Path("features/battle/art/obstacles/flasks")

# light, mid, dark tones of each liquid.
LIQUIDS = {
    "acid": ("#d6ff6e", "#7cc62d", "#2f6a0e"),
    "water": ("#a6e2ff", "#3e9ad8", "#174f8c"),
    "oil": ("#f0c46a", "#9a6a22", "#3c2608"),
    "electricity": ("#f6feff", "#7fe0ff", "#1f6fb4"),
}
EXPLOSIVE = ("#ffe08a", "#ff7a2a", "#9c1f0c")
GAS = ("#f7fdff", "#c4e6f4", "#6e9fb6")

GLASS_STROKE = "#e4f3ff"
CORK = ("#c08a55", "#8a5a32", "#4f2f17")
METAL = ("#eef2f5", "#9aa6ae", "#47525a")


def gradient(name, tones, x1="0", y1="0", x2="0", y2="1"):
    light, mid, dark = tones
    return (
        f'<linearGradient id="{name}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
        f'<stop offset="0" stop-color="{light}"/><stop offset="0.45" stop-color="{mid}"/>'
        f'<stop offset="1" stop-color="{dark}"/></linearGradient>'
    )


def glow(name, color, opacity):
    return (
        f'<radialGradient id="{name}" cx="0.5" cy="0.5" r="0.5">'
        f'<stop offset="0" stop-color="{color}" stop-opacity="{opacity}"/>'
        f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>'
    )


def svg(width, height, defs, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
        f"<defs>{''.join(defs)}</defs>{''.join(body)}</svg>\n"
    )


def shadow(cx, cy, rx, ry):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#000" opacity="0.38"/>'


def cork(x, y, w, h):
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="url(#cork)" stroke="{CORK[2]}" stroke-width="1.5"/>'
        f'<rect x="{x + 2}" y="{y + 2}" width="{w - 4}" height="3" rx="1.5" fill="{CORK[0]}" opacity="0.7"/>'
    )


def bubbles(points, color):
    return "".join(
        f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}" opacity="0.75"/>' for x, y, r in points
    )


def bolt(points):
    path = " ".join(f"{x},{y}" for x, y in points)
    return (
        f'<polygon points="{path}" fill="#fff7a8" stroke="#ffffff" stroke-width="1.2" stroke-linejoin="round"/>'
    )


# Round-bottom flask: neck x 41..59, bulb centered at (50, 92) with radius 36.
ROUND_BODY = "M41,22 L41,57.1 A36,36 0 1,0 59,57.1 L59,22 Z"


def round_flask(tones, extra, glow_color=None):
    defs = [gradient("liquid", tones), gradient("cork", CORK),
            f'<clipPath id="inside"><path d="{ROUND_BODY}"/></clipPath>']
    body = [shadow(50, 130, 33, 7)]
    if glow_color:
        defs.append(glow("halo", glow_color, 0.55))
        body.append('<circle cx="50" cy="92" r="52" fill="url(#halo)"/>')
    body += [
        f'<path d="{ROUND_BODY}" fill="#dff1ff" fill-opacity="0.16"/>',
        f'<g clip-path="url(#inside)"><rect x="0" y="70" width="100" height="70" fill="url(#liquid)"/>'
        f'<ellipse cx="50" cy="70" rx="34" ry="5" fill="{tones[0]}" opacity="0.85"/>{extra}</g>',
        f'<path d="{ROUND_BODY}" fill="none" stroke="{GLASS_STROKE}" stroke-width="3" stroke-opacity="0.9"/>',
        '<path d="M28,78 A26,26 0 0,0 30,110" fill="none" stroke="#ffffff" stroke-width="4" stroke-linecap="round" opacity="0.55"/>',
        '<path d="M45,26 L45,52" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" opacity="0.45"/>',
        f'<rect x="37" y="17" width="26" height="7" rx="3" fill="#e9f6ff" fill-opacity="0.55" stroke="{GLASS_STROKE}" stroke-width="2"/>',
        cork(42, 5, 16, 15),
    ]
    return svg(100, 140, defs, body)


# Conical flask: neck x 56..84, cone to a base 12..128 at y 134.
CONE_BODY = "M56,22 L56,50 L16,122 Q10,136 26,136 L114,136 Q130,136 124,122 L84,50 L84,22 Z"


def cone_flask(tones, extra, glow_color=None):
    defs = [gradient("liquid", tones), gradient("cork", CORK),
            f'<clipPath id="inside"><path d="{CONE_BODY}"/></clipPath>']
    body = [shadow(70, 140, 58, 8)]
    if glow_color:
        defs.append(glow("halo", glow_color, 0.5))
        body.append('<ellipse cx="70" cy="104" rx="70" ry="50" fill="url(#halo)"/>')
    body += [
        f'<path d="{CONE_BODY}" fill="#dff1ff" fill-opacity="0.16"/>',
        f'<g clip-path="url(#inside)"><rect x="0" y="78" width="140" height="70" fill="url(#liquid)"/>'
        f'<ellipse cx="70" cy="78" rx="40" ry="5" fill="{tones[0]}" opacity="0.85"/>{extra}</g>',
        f'<path d="{CONE_BODY}" fill="none" stroke="{GLASS_STROKE}" stroke-width="3.2" stroke-opacity="0.9" stroke-linejoin="round"/>',
        '<path d="M50,72 L28,114" stroke="#ffffff" stroke-width="4.5" stroke-linecap="round" opacity="0.5"/>',
        '<path d="M61,26 L61,48" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" opacity="0.45"/>',
        '<path d="M36,98 L46,98 M33,106 L41,106 M30,114 L44,114" stroke="#ffffff" stroke-width="1.6" opacity="0.5"/>',
        f'<rect x="51" y="16" width="38" height="8" rx="3.5" fill="#e9f6ff" fill-opacity="0.55" stroke="{GLASS_STROKE}" stroke-width="2"/>',
        cork(58, 3, 24, 16),
    ]
    return svg(140, 150, defs, body)


def liquid_details(kind, cone):
    """Bubbles, sheen or sparks inside the liquid; coordinates suit each silhouette."""
    light, _mid, dark = LIQUIDS[kind]
    if kind == "electricity":
        if cone:
            return bolt([(76, 82), (58, 108), (70, 108), (60, 132), (86, 100), (73, 100), (82, 82)])
        return bolt([(56, 74), (40, 98), (51, 98), (43, 120), (64, 92), (53, 92), (61, 74)])
    if kind == "oil":
        sheen = (f'<ellipse cx="{58 if cone else 44}" cy="{98 if cone else 88}" rx="{18 if cone else 12}" ry="4" '
                 f'fill="{light}" opacity="0.45"/>')
        return sheen + bubbles([(80, 118, 2.5), (52, 124, 2)] if cone else [(60, 108, 2.5), (40, 112, 2)], dark)
    points = ([(60, 100, 4), (78, 116, 3), (88, 94, 2.5), (48, 122, 2.5)] if cone
              else [(42, 98, 4), (58, 110, 3), (62, 86, 2.5), (36, 116, 2)])
    return bubbles(points, light)


def pressure_flask():
    defs = [gradient("gas", GAS), gradient("metal", METAL, "0", "0", "1", "0"),
            glow("halo", "#dff6ff", 0.45),
            '<clipPath id="inside"><rect x="24" y="36" width="62" height="96" rx="18"/></clipPath>']
    swirl = ('<path d="M36,62 C46,52 66,52 74,62" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.75"/>'
             '<path d="M38,104 C48,96 64,96 72,104" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.75"/>'
             '<path d="M44,116 C52,111 60,111 66,116" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" opacity="0.55"/>'
             '<path d="M46,70 C52,66 60,66 64,70" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" opacity="0.55"/>')
    body = [
        shadow(55, 142, 36, 7),
        '<ellipse cx="55" cy="86" rx="52" ry="60" fill="url(#halo)"/>',
        f'<g clip-path="url(#inside)"><rect x="0" y="30" width="110" height="110" fill="url(#gas)"/>{swirl}</g>',
        f'<rect x="24" y="36" width="62" height="96" rx="18" fill="none" stroke="{GLASS_STROKE}" stroke-width="3"/>',
        '<path d="M33,52 L33,116" stroke="#ffffff" stroke-width="4" stroke-linecap="round" opacity="0.55"/>',
        # Steel bands, caps and the gauge on top.
        f'<rect x="18" y="124" width="74" height="16" rx="4" fill="url(#metal)" stroke="{METAL[2]}" stroke-width="1.5"/>',
        f'<rect x="18" y="30" width="74" height="14" rx="4" fill="url(#metal)" stroke="{METAL[2]}" stroke-width="1.5"/>',
        f'<rect x="20" y="79" width="70" height="10" rx="2" fill="#d23b2a" stroke="{METAL[2]}" stroke-width="1.2"/>',
        '<path d="M30,79 L24,89 M42,79 L36,89 M54,79 L48,89 M66,79 L60,89 M78,79 L72,89 M90,79 L84,89" stroke="#ffe9d6" stroke-width="3"/>',
        f'<rect x="50" y="18" width="10" height="14" fill="url(#metal)" stroke="{METAL[2]}" stroke-width="1.2"/>',
        f'<circle cx="55" cy="15" r="13" fill="#f4f1e6" stroke="{METAL[2]}" stroke-width="3"/>',
        '<path d="M46,15 A9,9 0 0,1 64,15" fill="none" stroke="#d23b2a" stroke-width="2.5"/>',
        '<line x1="55" y1="15" x2="62" y2="8" stroke="#2b2b2b" stroke-width="2.2" stroke-linecap="round"/>',
        '<circle cx="55" cy="15" r="2.2" fill="#2b2b2b"/>',
        # Escaping puffs of pressure.
        '<circle cx="90" cy="26" r="5" fill="#ffffff" opacity="0.55"/><circle cx="99" cy="18" r="3.5" fill="#ffffff" opacity="0.4"/>',
    ]
    return svg(110, 150, defs, body)


def explosive_flask():
    sparks = "".join(
        f'<circle cx="{x}" cy="{y}" r="{r}" fill="#ffd24a"/>' for x, y, r in [(66, 6, 2.6), (74, 12, 1.8), (60, 2, 1.6)]
    )
    hazard = (
        '<polygon points="50,78 66,106 34,106" fill="#ffd23c" stroke="#2a1a0a" stroke-width="2.5" stroke-linejoin="round"/>'
        '<rect x="48" y="86" width="4" height="11" rx="1.5" fill="#2a1a0a"/>'
        '<circle cx="50" cy="101.5" r="2.3" fill="#2a1a0a"/>'
    )
    extra = bubbles([(66, 116, 3), (36, 116, 2.5), (62, 86, 2)], EXPLOSIVE[0]) + hazard
    defs = [gradient("liquid", EXPLOSIVE), gradient("cork", CORK), glow("halo", "#ff8a2a", 0.6),
            f'<clipPath id="inside"><path d="{ROUND_BODY}"/></clipPath>']
    body = [
        shadow(50, 130, 33, 7),
        '<circle cx="50" cy="92" r="54" fill="url(#halo)"/>',
        f'<path d="{ROUND_BODY}" fill="#dff1ff" fill-opacity="0.16"/>',
        f'<g clip-path="url(#inside)"><rect x="0" y="62" width="100" height="80" fill="url(#liquid)"/>'
        f'<ellipse cx="50" cy="62" rx="32" ry="5" fill="{EXPLOSIVE[0]}" opacity="0.85"/>{extra}</g>',
        f'<path d="{ROUND_BODY}" fill="none" stroke="{GLASS_STROKE}" stroke-width="3" stroke-opacity="0.9"/>',
        '<path d="M28,78 A26,26 0 0,0 30,110" fill="none" stroke="#ffffff" stroke-width="4" stroke-linecap="round" opacity="0.5"/>',
        f'<rect x="37" y="17" width="26" height="7" rx="3" fill="#e9f6ff" fill-opacity="0.55" stroke="{GLASS_STROKE}" stroke-width="2"/>',
        cork(42, 5, 16, 15),
        # A short fuse with sparks.
        '<path d="M53,6 Q58,0 64,7" fill="none" stroke="#3a2a1a" stroke-width="2.4" stroke-linecap="round"/>',
        sparks,
    ]
    return svg(100, 140, defs, body)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    files = {}
    for kind, tones in LIQUIDS.items():
        glow_color = "#9fe8ff" if kind == "electricity" else None
        files[f"flask_{kind}.svg"] = round_flask(tones, liquid_details(kind, False), glow_color)
        files[f"big_flask_{kind}.svg"] = cone_flask(tones, liquid_details(kind, True), glow_color)
    files["pressure_flask.svg"] = pressure_flask()
    files["explosive_flask.svg"] = explosive_flask()
    for name, text in files.items():
        # LF line endings, as the repository stores text.
        (OUTPUT / name).write_bytes(text.encode("utf-8"))
    print(f"Wrote {len(files)} files to {OUTPUT}")


if __name__ == "__main__":
    main()
