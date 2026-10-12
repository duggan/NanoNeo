"""Generates NanoNeo's artwork as SVG, from one drawing of the AlphaSmart Neo 2 seen
from above. `make icons` renders these into the files in Resources/.

Geometry is in "units": the body is 100 wide and 80 tall, measured from a photo.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CREAM = "#F4EDD8"
INK = "#26303A"
BODY = "#33363D"
RECESS = "#24272C"
KEY = "#4A4F58"
LCD = "#C9D4B2"

# Body silhouette: an arched top edge, sides that flare out to full width about
# 58% of the way down, and a slightly bowed base.
BODY_PATH = (
    "M 18.6,3.4 Q 50,-3.3 81.4,3.4 "
    "C 96,22 98,38 100,58 L 100,71 Q 100,76.2 96,76.6 "
    "Q 50,82.6 4,76.6 Q 0,76.2 0,71 L 0,58 "
    "C 2,38 4,22 18.6,3.4 Z"
)
SCREEN = (25.6, 12.3, 46.2, 13.0)  # x, y, w, h
# Keyboard recess, with the arrow-key block dropping lower at bottom right.
RECESS_PATH = (
    "M 6.4,35.4 L 94.4,35.4 Q 95.7,35.4 95.7,36.7 L 95.7,73.6 Q 95.7,74.9 94.4,74.9 "
    "L 75.7,74.9 Q 74.4,74.9 74.4,73.6 L 74.4,71.8 L 6.4,71.8 Q 5.1,71.8 5.1,70.5 "
    "L 5.1,36.7 Q 5.1,35.4 6.4,35.4 Z"
)
# Key rows: (y centre, number of keys). The file-key row on top has smaller keys.
ROWS = [(38.4, 17), (44.4, 14), (50.5, 14), (56.6, 13), (62.6, 12)]


def keycaps():
    out = []
    x0, x1 = 6.6, 94.2
    for y, n in ROWS:
        pitch = (x1 - x0) / n
        w = pitch * 0.78
        h = 4.6 if y > 40 else 3.2
        for i in range(n):
            x = x0 + i * pitch + (pitch - w) / 2
            out.append(f'<rect x="{x:.2f}" y="{y - h / 2:.2f}" width="{w:.2f}" height="{h:.2f}" rx="0.8"/>')
    # Bottom row: ctrl, alt, cmd, space bar, esc, delete; then the arrow keys.
    for a, b in ((6.6, 11.6), (12.6, 17.6), (18.6, 23.6), (25.0, 54.6), (56.0, 61.0), (62.0, 67.0)):
        out.append(f'<rect x="{a:.2f}" y="66.1" width="{b - a:.2f}" height="4.6" rx="0.8"/>')
    for a, y in ((76.0, 68.0), (82.6, 68.0), (89.2, 68.0), (76.0, 72.6), (82.6, 72.6), (89.2, 72.6)):
        out.append(f'<rect x="{a:.2f}" y="{y - 1.9:.2f}" width="5.2" height="3.8" rx="0.7"/>')
    return "".join(out)


def app_icon():
    s = 6.6
    ox, oy = 512 - 50 * s, 512 - 40 * s
    sx, sy, sw, sh = SCREEN
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect x="100" y="112" width="824" height="824" rx="185" fill="#000" fill-opacity="0.18"/>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="{CREAM}"/>
  <g transform="translate({ox:.2f} {oy:.2f}) scale({s})">
    <path d="{BODY_PATH}" fill="{BODY}"/>
    <rect x="{sx - 2.2}" y="{sy - 2.2}" width="{sw + 4.4}" height="{sh + 4.4}" rx="2.6" fill="{RECESS}"/>
    <rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="1" fill="{LCD}"/>
    <path d="{RECESS_PATH}" fill="{RECESS}"/>
    <g fill="{KEY}">{keycaps()}</g>
  </g>
</svg>
'''


def menu_bar_glyph(lit=False):
    """Template image, 22x18 pt: the silhouette with the screen and three rows of
    keys knocked out. `lit` fills the screen back in, for the syncing state."""
    s = 0.21
    ox, oy = 11 - 50 * s, 9 - 40 * s
    sx, sy, sw, sh = SCREEN
    holes = f" M {sx - 2},{sy - 3} h {sw + 4} v {sh + 6} h {-(sw + 4)} Z"
    pitch = 80 / 9
    for y in (45, 55, 65):
        for i in range(9):
            x = 10 + i * pitch + pitch * 0.2
            holes += f" M {x:.1f},{y} h {pitch * 0.6:.1f} v 5 h {-pitch * 0.6:.1f} Z"
    screen = (f'<rect x="{sx + 3}" y="{sy + 2}" width="{sw - 6}" height="{sh - 4}" rx="1" fill="#000"/>'
              if lit else "")
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 22 18" width="22" height="18">
  <g transform="translate({ox:.3f} {oy:.3f}) scale({s})">
    <path fill-rule="evenodd" fill="#000" d="{BODY_PATH}{holes}"/>
    {screen}
  </g>
</svg>
'''


def dmg_background():
    """660x420 window: cream, with an arrow from the app (175, 215) to Applications (485, 215)."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 660 420" width="660" height="420">
  <rect width="660" height="420" fill="{CREAM}"/>
  <g fill="none" stroke="{INK}" stroke-opacity="0.55" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">
    <path d="M268,215 L392,215"/>
    <path d="M372,197 L392,215 L372,233"/>
  </g>
  <text x="330" y="335" text-anchor="middle" font-family="-apple-system, Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="17" fill="{INK}" fill-opacity="0.7">Drag NanoNeo to your Applications folder</text>
</svg>
'''


if __name__ == "__main__":
    for name, svg in (("AppIcon.svg", app_icon()),
                      ("MenuBarIcon.svg", menu_bar_glyph()),
                      ("MenuBarIconSyncing.svg", menu_bar_glyph(lit=True)),
                      ("DMGBackground.svg", dmg_background())):
        with open(os.path.join(HERE, name), "w") as f:
            f.write(svg)
        print("wrote", name)
