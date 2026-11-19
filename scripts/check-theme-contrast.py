#!/usr/bin/env python3
"""校验 ThemePresets.swift 里 20×2 套主题的正文/次级/三级文本对比度。"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRESETS = ROOT / "Sources/Causality/Theme/ThemePresets.swift"


def rgb(hex_value: int) -> tuple[float, float, float]:
    return (
        ((hex_value >> 16) & 0xFF) / 255,
        ((hex_value >> 8) & 0xFF) / 255,
        (hex_value & 0xFF) / 255,
    )


def luminance(hex_value: int) -> float:
    def channel(value: float) -> float:
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    red, green, blue = rgb(hex_value)
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)


def contrast(a: int, b: int) -> float:
    first, second = sorted((luminance(a), luminance(b)), reverse=True)
    return (first + 0.05) / (second + 0.05)


def mix(a: int, b: int, amount: float) -> int:
    def channel(value: int, shift: int) -> int:
        return (value >> shift) & 0xFF

    def blend(shift: int) -> int:
        return round(channel(a, shift) * (1 - amount) + channel(b, shift) * amount)

    return (blend(16) << 16) | (blend(8) << 8) | blend(0)


def ensure_contrast(foreground: int, backgrounds: list[int], target: float) -> int:
    worst = min(backgrounds, key=lambda background: contrast(foreground, background))
    if contrast(foreground, worst) >= target:
        return foreground
    direction = 0x000000 if luminance(worst) > 0.5 else 0xFFFFFF
    low, high = 0.0, 1.0
    for _ in range(24):
        middle = (low + high) / 2
        if contrast(mix(foreground, direction, middle), worst) >= target:
            high = middle
        else:
            low = middle
    return mix(foreground, direction, high)


pattern = re.compile(
    r"static let (\w+?)(Light|Dark) = Theme\.make\(\s*"
    r"isDark: (true|false),\s*\(\s*"
    r"background: 0x([0-9A-Fa-f]{6}),\s*"
    r"panel: 0x([0-9A-Fa-f]{6}),\s*"
    r"card: 0x([0-9A-Fa-f]{6}),\s*"
    r"imageWell: 0x([0-9A-Fa-f]{6}),\s*"
    r"textPrimary: 0x([0-9A-Fa-f]{6}),\s*"
    r"textSecondary: 0x([0-9A-Fa-f]{6}),\s*"
    r"border: 0x([0-9A-Fa-f]{6}),\s*"
    r"accent: 0x([0-9A-Fa-f]{6})",
    re.S,
)
blocks = pattern.findall(PRESETS.read_text())
failures: list[str] = []
minimum = {"primary": 99.0, "secondary": 99.0, "tertiary": 99.0}

for name, mode, _dark, *values in blocks:
    background, panel, card, _image, primary_raw, secondary_raw, _border, _accent = [
        int(value, 16) for value in values
    ]
    backgrounds = [background, panel, card]
    primary = ensure_contrast(primary_raw, backgrounds, 4.5)
    secondary = ensure_contrast(secondary_raw, backgrounds, 4.5)
    tertiary = mix(secondary, background, 0.18)
    for label, color, target in (
        ("primary", primary, 4.5),
        ("secondary", secondary, 4.5),
        ("tertiary", tertiary, 3.0),
    ):
        ratio = min(contrast(color, item) for item in backgrounds)
        minimum[label] = min(minimum[label], ratio)
        if ratio + 1e-9 < target:
            failures.append(f"{name}{mode}: {label} {ratio:.2f} < {target}")

if len(blocks) != 40:
    failures.append(f"期望 40 个主题块，实际 {len(blocks)}")

if failures:
    print("配色对比度失败：")
    for item in failures:
        print("  ✗", item)
    sys.exit(1)

print(
    "  ✓ 20×2 套配色：主文本 {:.2f} / 次级 {:.2f} / 三级 {:.2f} 最低对比度".format(
        minimum["primary"], minimum["secondary"], minimum["tertiary"]
    )
)
