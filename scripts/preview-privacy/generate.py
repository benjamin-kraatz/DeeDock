"""Generate fictional window thumbnails. Requires Pillow on macOS."""
import argparse
import random
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Families stay together across all appearances, sizes, and categories.
FAMILIES = {
    "train": ("browser", "workspace", "editor", "dashboard", "mail", "preferences"),
    "validation": ("portal", "inspector"),
    "test": ("library", "metrics", "review"),
}
LAYOUTS = {
    # Overlay position, base width, base height, background layout.
    "browser": (.50, .51, .49, .55, "columns"),
    "workspace": (.76, .57, .42, .64, "rows"),
    "editor": (.29, .54, .47, .64, "sidebar"),
    "dashboard": (.59, .42, .57, .48, "tiles"),
    "mail": (.67, .67, .56, .48, "sidebar"),
    "preferences": (.46, .45, .49, .72, "rows"),
    "portal": (.39, .68, .56, .48, "tiles"),
    "inspector": (.79, .43, .39, .61, "columns"),
    "library": (.51, .76, .69, .37, "columns"),
    "metrics": (.73, .29, .42, .51, "tiles"),
    "review": (.31, .67, .47, .51, "sidebar"),
}
CATEGORIES = ("signin", "code", "private-chat", "docs", "number", "public-chat", "ordinary")
BUDGETS = ((160, 100), (240, 150), (320, 200), (480, 300), (640, 400), (800, 500))
WINDOWS = ((1280, 800), (1440, 900), (1050, 860), (1536, 864), (960, 960), (860, 1100))


@lru_cache
def font(size):
    return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size)


def render(family, category, variant):
    rng = random.Random(f"{family}-{category}-{variant}")
    w, h = WINDOWS[variant % len(WINDOWS)]
    budget = BUDGETS[(variant // len(WINDOWS) + variant) % len(BUDGETS)]
    dark = (variant + variant // len(WINDOWS)) % 2
    bg, panel, ink, muted, line = (
        ("#181a20", "#2a2d38", "#f4f4f8", "#b5bac9", "#454957") if dark else
        ("#e9edf4", "#ffffff", "#202635", "#4c576d", "#c4ccda")
    )
    accent = rng.choice(("#3769d4", "#8056b4", "#147d76", "#a04b61"))
    image = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(image)

    def box(x, y, width, height, color, radius=9, outline=None):
        d.rounded_rectangle((x, y, x+width, y+height), radius, fill=color, outline=outline, width=2)

    def label(x, y, title, size=24, color=ink):
        d.text((x, y), title, font=font(size), fill=color)

    cx, cy, fw, fh, shell = LAYOUTS[family]
    box(0, 0, w, 61, panel, 0)
    for i, color in enumerate(("#e76967", "#eabb42", "#59be68")):
        d.ellipse((18+i*22, 23, 30+i*22, 35), fill=color)
    label(98, 16, rng.choice(("Fern Workspace", "Northstar", "Orchard", "Field Notes")), 24)
    cols = {"columns": 2, "tiles": 3, "rows": 1, "sidebar": 2}[shell]
    for col in range(cols):
        for row in range(1 if shell == "sidebar" else 4):
            width = (w - 100) // cols
            x, y = 33 + col * (width + 12), 89 + row * ((h - 105) // 4)
            if shell == "sidebar":
                width = int(w * (.22 if col == 0 else .68))
                x = 33 if col == 0 else int(w * .27)
            box(x, y, width, (h - 120) if shell == "sidebar" else (h - 140) // 4, panel)
            label(x+16, y+12, rng.choice(("Overview", "Activity", "Library", "Projects", "Notes")), 24, muted)
            for i in range(5):
                box(x+18, y+51+i*12, int((width-36) * rng.uniform(.35, .90)), 4, line, 2)

    pw, ph = int(w * (fw + rng.uniform(-.045, .045))), int(h * (fh + rng.uniform(-.045, .045)))
    x = int(w * cx - pw / 2 + rng.uniform(-.04, .04) * w)
    y = int(h * cy - ph / 2 + rng.uniform(-.04, .04) * h)
    if variant % 3 == 0 and category != "ordinary":
        image = Image.blend(image, Image.new("RGB", image.size, "#10121c"), .22)
        d = ImageDraw.Draw(image)
    if category != "ordinary" or variant % 2:
        box(x+4, y+7, pw, ph, line, 17)
        box(x, y, pw, ph, panel, 16, line)

    tx, ty = x+int(pw*.07), y+int(ph*.09)
    step = int(ph*.15)
    size = max(19, min(32, pw//13))
    if category == "signin":
        label(tx, ty, rng.choice(("Sign in", "Log in to continue", "Welcome back")), size)
        for i, value in enumerate(("Email address", "Password")):
            box(tx, ty+step*(i*2+1), int(pw*.85), int(step*1.4), bg, outline=line)
            label(tx+9, ty+step*(i*2+1)+5, value, size-4, muted)
        box(tx, ty+step*5, int(pw*.57), step, accent)
        label(tx+9, ty+step*5+1, "Continue", size-4, "white")
    elif category in ("code", "number"):
        label(tx, ty, rng.choice(("Verification code", "Security code", "One-time code"))
              if category == "code" else rng.choice(("Order number", "Reference", "Inventory count")), size)
        label(tx, ty+step, "Enter the code to continue" if category == "code" else "Details for this record", size-6, muted)
        digits = f"{rng.randrange(100000, 1000000)}"
        if variant % 3 == 0:
            label(tx, ty+step*3, "  ".join(digits), size+7)
        else:
            for i, digit in enumerate(digits):
                dx = tx + int(i * pw * .135)
                box(dx, ty+step*3, int(pw*.108), int(step*1.25), bg, outline=line)
                label(dx+6, ty+step*3+2, digit, size)
    elif category in ("private-chat", "public-chat"):
        label(tx, ty, rng.choice(("Direct message", "Private chat", "Message to Riley"))
              if category == "private-chat" else rng.choice(("# announcements", "# general", "Public channel")), size)
        for i, message in enumerate(("Riley: Thanks for sending that.", "Sam: I'll check this morning.", "Riley: Sounds good!")):
            bx = tx + int(pw * .12) * (i % 2)
            box(bx, ty+step*(i+1), int(pw*.70), step-4, bg if i != 1 else line)
            label(bx+7, ty+step*(i+1)+5, message, max(14, size-9))
        box(tx, ty+step*5, int(pw*.84), step, bg, outline=line)
        label(tx+8, ty+step*5+3, "Write a message", size-7, muted)
    elif category == "docs":
        label(tx, ty, rng.choice(("Sign-in help", "Password guide", "Login documentation")), size)
        for i, paragraph in enumerate(("Open your account settings.", "Choose a password or passkey.",
                                       "Keep your verification code private.", "Troubleshoot access to your account.")):
            label(tx, ty+step*(i+1), paragraph, max(13, size-9), muted)
    elif variant % 2:
        label(tx, ty, rng.choice(("Export options", "Release notes", "Project status")), size)
        for i in range(4):
            box(tx, ty+step*(i+1), int(pw*rng.uniform(.28, .82)), 7, line, 3)

    fit = min(budget[0] / w, budget[1] / h)
    return image.resize((round(w*fit), round(h*fit)), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--split", choices=FAMILIES)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    for split, families in FAMILIES.items():
        if args.split and args.split != split:
            continue
        for family in families:
            for category in CATEGORIES:
                label = "sensitive" if category in CATEGORIES[:3] else "ordinary"
                directory = args.output / split / label
                directory.mkdir(parents=True, exist_ok=True)
                for variant in range(24):
                    render(family, category, variant).save(directory / f"{category}_{family}_{variant:02d}.png")


if __name__ == "__main__":
    main()
