"""Puts an Android phone frame around each app screenshot, so the documentation pictures look like
screenshots taken on the station's Android phone (720 x 1600 pixels): the status bar on top (time,
notification icons, sound off, Wi-Fi, signal, battery) and the navigation bar at the bottom
(Recent apps, Home, Back).

usage: python3 frame.py <folder with the 720 x 1436 screenshots> <output folder> [logo.png]
The screenshots come from shots.js (360 x 718 dp at 2x)."""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

W, STATUS, NAV = 720, 68, 96
S = 4  # draw 4x larger, then shrink (smooth edges)
GREY = (74, 74, 74)
LIGHT = (176, 176, 176)
NAV_BG = (244, 244, 244)
NAV_ICON = (96, 96, 96)
FONT_BOLD = '/usr/share/fonts/opentype/inter/Inter-SemiBold.otf'
FONT_NUM = '/usr/share/fonts/opentype/inter/Inter-Bold.otf'


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', size)


def bubble(d, cx, cy, r, fill, tail='left'):
    """Chat bubble (Messenger-like or a plain message bubble)."""
    d.ellipse((cx - r, cy - r * 0.92, cx + r, cy + r * 0.92), fill=fill)
    if tail == 'left':
        d.polygon([(cx - r * 0.55, cy + r * 0.55), (cx - r * 0.85, cy + r * 1.05), (cx - r * 0.1, cy + r * 0.8)], fill=fill)
    else:
        d.polygon([(cx + r * 0.35, cy + r * 0.6), (cx + r * 0.9, cy + r * 1.0), (cx + r * 0.75, cy + r * 0.3)], fill=fill)


def status_bar(clock, logo):
    img = Image.new('RGB', (W * S, STATUS * S), 'white')
    d = ImageDraw.Draw(img)
    y = 34 * S  # middle line of the icons
    # Time
    f = font(FONT_BOLD, 25 * S)
    d.text((30 * S, y), clock, fill=GREY, font=f, anchor='lm')
    x = 30 * S + d.textlength(clock, font=f) + 14 * S
    # Messenger
    r = 11 * S
    bubble(d, x + r, y, r, GREY)
    zz = [(x + r - 6 * S, y + 3 * S), (x + r - 2 * S, y - 3 * S), (x + r + 1 * S, y + 1 * S), (x + r + 6 * S, y - 4 * S)]
    d.line(zz, fill='white', width=int(2.4 * S), joint='curve')
    x += 2 * r + 8 * S
    # The station app (Mangao logo in a circle)
    if logo is not None:
        size = 25 * S
        lg = Image.new('RGBA', (size, size), 'white')
        lg.alpha_composite(logo.convert('RGBA').resize((size, size), Image.LANCZOS))
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
        img.paste(lg, (int(x), int(y - size / 2)), mask)
        x += size + 9 * S
    # Messages (two bubbles)
    bubble(d, x + 9 * S, y - 1 * S, 9 * S, GREY, 'left')
    bubble(d, x + 15 * S, y + 2 * S, 8 * S, GREY, 'right')
    x += 34 * S
    # More notifications dot
    d.ellipse((x + 4 * S, y - 4 * S, x + 12 * S, y + 4 * S), fill=GREY)

    # Right side, from the right edge: battery, two signal bars, Wi-Fi, sound off
    bx2 = W * S - 30 * S
    bw, bh = 46 * S, 28 * S
    bx1 = bx2 - bw
    d.rounded_rectangle((bx1, y - bh / 2, bx2, y + bh / 2), radius=bh / 2, fill=(200, 200, 200))
    d.rounded_rectangle((bx1, y - bh / 2, bx1 + bw * 0.72, y + bh / 2), radius=bh / 2, fill=(88, 88, 88))
    d.rectangle((bx1 + bw * 0.5, y - bh / 2, bx1 + bw * 0.72, y + bh / 2), fill=(88, 88, 88))
    d.text(((bx1 + bx2) / 2, y + 1 * S), '64', fill='white', font=font(FONT_NUM, 19 * S), anchor='mm')
    x = bx1 - 12 * S
    for _ in range(2):  # two SIM signal bars (no service: light grey)
        for i in range(4):
            h = (6 + i * 5) * S
            xx = x - (3 - i) * 6 * S
            d.rounded_rectangle((xx - 3 * S, y + 11 * S - h, xx, y + 11 * S), radius=1 * S, fill=LIGHT if i > 0 else GREY)
        x -= 32 * S
    # Wi-Fi with "5" and the up/down arrows
    wx = x - 16 * S
    for i, rr in enumerate((22, 15, 8)):
        d.arc((wx - rr * S, y + 8 * S - rr * S, wx + rr * S, y + 8 * S + rr * S), 225, 315, fill=GREY, width=int(3.2 * S))
    d.ellipse((wx - 3 * S, y + 6 * S, wx + 3 * S, y + 12 * S), fill=GREY)
    d.text((wx + 14 * S, y - 9 * S), '5', fill=GREY, font=font(FONT_BOLD, 12 * S), anchor='mm')
    ax = wx + 11 * S
    d.line([(ax, y), (ax, y + 11 * S)], fill=GREY, width=int(2 * S))
    d.polygon([(ax - 3 * S, y + 8 * S), (ax + 3 * S, y + 8 * S), (ax, y + 12 * S)], fill=GREY)
    ax2 = wx + 17 * S
    d.line([(ax2, y + 1 * S), (ax2, y + 12 * S)], fill=GREY, width=int(2 * S))
    d.polygon([(ax2 - 3 * S, y + 3 * S), (ax2 + 3 * S, y + 3 * S), (ax2, y - 1 * S)], fill=GREY)
    x = wx - 40 * S
    # Sound off (speaker with a slash and a wave)
    sx = x
    d.polygon([(sx - 12 * S, y - 5 * S), (sx - 6 * S, y - 5 * S), (sx + 1 * S, y - 12 * S), (sx + 1 * S, y + 12 * S),
               (sx - 6 * S, y + 5 * S), (sx - 12 * S, y + 5 * S)], fill=GREY)
    d.line([(sx - 14 * S, y - 13 * S), (sx + 8 * S, y + 13 * S)], fill='white', width=int(5 * S))
    d.line([(sx - 14 * S, y - 13 * S), (sx + 8 * S, y + 13 * S)], fill=GREY, width=int(2.4 * S))
    d.line([(sx + 7 * S, y - 10 * S), (sx + 10 * S, y - 5 * S), (sx + 6 * S, y), (sx + 10 * S, y + 5 * S), (sx + 7 * S, y + 10 * S)],
           fill=GREY, width=int(2.2 * S), joint='curve')
    return img.resize((W, STATUS), Image.LANCZOS)


def nav_bar():
    img = Image.new('RGB', (W * S, NAV * S), NAV_BG)
    d = ImageDraw.Draw(img)
    y = 46 * S
    lw = int(2.6 * S)
    # Recent apps |||
    for i in range(3):
        xx = (149 + i * 12) * S
        d.line([(xx, y - 13 * S), (xx, y + 13 * S)], fill=NAV_ICON, width=lw)
    # Home: rounded square
    d.rounded_rectangle((349 * S, y - 13 * S, 377 * S, y + 14 * S), radius=8 * S, outline=NAV_ICON, width=lw)
    # Back <
    d.line([(574 * S, y - 15 * S), (559 * S, y), (574 * S, y + 15 * S)], fill=NAV_ICON, width=lw, joint='curve')
    return img.resize((W, NAV), Image.LANCZOS)


def frame(src, dst, clock, logo):
    shot = Image.open(src).convert('RGB')
    if shot.size != (W, 1436):
        shot = shot.resize((W, int(shot.height * W / shot.width)), Image.LANCZOS).crop((0, 0, W, 1436))
    out = Image.new('RGB', (W, STATUS + 1436 + NAV), 'white')
    out.paste(status_bar(clock, logo), (0, 0))
    out.paste(shot, (0, STATUS))
    out.paste(nav_bar(), (0, STATUS + 1436))
    out.save(dst)


if __name__ == '__main__':
    src_dir, out_dir = sys.argv[1], sys.argv[2]
    logo = Image.open(sys.argv[3]) if len(sys.argv) > 3 else None
    os.makedirs(out_dir, exist_ok=True)
    names = sorted(n for n in os.listdir(src_dir) if n.endswith('.png'))
    for i, n in enumerate(names):
        # A morning of testing: 8:04, 8:05, ... (one or two minutes between pictures)
        m = 4 + i + i // 3
        frame(os.path.join(src_dir, n), os.path.join(out_dir, n), f'8:{m:02d}', logo)
        print('framed', n)
