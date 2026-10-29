#!/usr/bin/env python3
"""Minimal, declared redactions for the third-party (Slack and Discord) screenshots.

These images were captured on the maintainer's machine. We keep them, but remove:

  slack-install-app.png                         app switcher with a truncated real app name (solid box)
  discord-setup-applications.png                browser toolbar: URL bar, extension icons (crop)
  discord-setup-oauth-url.png                   client_id value (solid box)
  discord-setup-authorize-dialog.png            the signed-in Discord handle and the debug app's name,
                                                twice (solid boxes; the dialog still shows the
                                                permissions list and the Authorize button)

Boxes use the colour sampled next to the box, so they read as empty space. No blur.
Each edit checks the source dimensions first, so running the script twice is a no-op.

Usage (Pillow required): python3 screenshots/scripts/redact-third-party.py
"""
import os
import sys
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "output")


def load(name, expected_size):
    path = os.path.join(OUT, name)
    img = Image.open(path).convert("RGB")
    if img.size != expected_size:
        print(f"skip {name}: {img.size} is not the original {expected_size} (already edited?)")
        return None, path
    return img, path


def box(img, rect, sample_at):
    """Fill rect (x0, y0, x1, y1) with the colour at sample_at."""
    colour = img.getpixel(sample_at)
    img.paste(colour, rect)


def main():
    img, path = load("slack-install-app.png", (992, 334))
    if img:
        box(img, (40, 44, 254, 100), (20, 70))  # app switcher, left rail background
        img.save(path); print("ok slack-install-app.png")

    img, path = load("discord-setup-applications.png", (1522, 539))
    if img:
        img.crop((0, 41, 1522, 539)).save(path); print("ok discord-setup-applications.png")

    img, path = load("discord-setup-oauth-url.png", (1406, 208))
    if img:
        box(img, (383, 156, 542, 180), (1000, 168))  # client_id digits, input background
        img.save(path); print("ok discord-setup-oauth-url.png")


    img, path = load("discord-setup-authorize-dialog.png", (506, 804))
    if img:
        box(img, (144, 148, 318, 172), (110, 160))  # app name in the heading, dialog background
        box(img, (209, 207, 306, 226), (110, 160))  # handle after "Signed in as", dialog background
        box(img, (255, 283, 374, 300), (430, 292))  # app name in the permissions sentence, panel background
        img.save(path); print("ok discord-setup-authorize-dialog.png")


if __name__ == "__main__":
    sys.exit(main())
