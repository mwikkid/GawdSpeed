# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Earl Scioneaux, III
#
# Draws the DMG window background (Branding/dmg-background*.png): "Drag
# GawdSpeed to Applications" with an arrow between the two icon slots, and a
# quieter Docs area below. Needs Pillow; the PNGs are committed, so releases
# don't. Icon slot positions must match scripts/release.sh (APP_X etc.).

from PIL import Image, ImageDraw, ImageFont

W, H = 640, 400                      # window content size, points
# Compact enough to fit when Finder's tab bar and path bar are on (they take
# about 55 pt from the window), which squeezed the first layout.
APP, APPS, DOCS = (170, 140), (470, 140), (300, 268)
INK, MUTED, ACCENT = (28, 31, 36), (120, 126, 136), (226, 140, 38)
FONT = "/System/Library/Fonts/HelveticaNeue.ttc"   # face 0 regular, 1 bold

def draw(scale):
    im = Image.new("RGB", (W * scale, H * scale))
    d = ImageDraw.Draw(im)
    for y in range(H * scale):       # soft vertical gradient
        t = y / (H * scale)
        c = tuple(int(a + (b - a) * t) for a, b in zip((248, 248, 250), (236, 237, 242)))
        d.line([(0, y), (W * scale, y)], fill=c)
    def font(size, bold):
        return ImageFont.truetype(FONT, size * scale, index=1 if bold else 0)
    title = "Drag GawdSpeed to Applications"
    f = font(19, True)
    w = d.textlength(title, font=f)
    d.text(((W * scale - w) / 2, 26 * scale), title, font=f, fill=INK)
    sub = "then open it from your Applications folder"
    f2 = font(12, False)
    w2 = d.textlength(sub, font=f2)
    d.text(((W * scale - w2) / 2, 53 * scale), sub, font=f2, fill=MUTED)
    # Arrow from the app slot to the Applications slot.
    y = APP[1] * scale
    x0, x1 = (APP[0] + 62) * scale, (APPS[0] - 62) * scale
    d.line([(x0, y), (x1 - 14 * scale, y)], fill=ACCENT, width=5 * scale)
    d.polygon([(x1, y), (x1 - 18 * scale, y - 11 * scale), (x1 - 18 * scale, y + 11 * scale)], fill=ACCENT)
    # A hairline separating the Docs area.
    d.line([(60 * scale, 214 * scale), ((W - 60) * scale, 214 * scale)], fill=(214, 216, 222), width=scale)
    # Caption beside the Docs folder (icons are 80 pt, so it starts past the icon).
    f3 = font(12, False)
    d.text(((DOCS[0] + 52) * scale, (DOCS[1] - 8) * scale), "Guide and license", font=f3, fill=MUTED)
    return im

draw(1).save("Branding/dmg-background.png")
draw(2).save("Branding/dmg-background@2x.png")
print("wrote Branding/dmg-background.png and @2x")
