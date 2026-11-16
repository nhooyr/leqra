#!/usr/bin/env python3
"""Render app icons from the versioned favicon.svg using Inkscape 1.2 or newer.

From the repository root: ./scripts/gen-icons.sh
Requires the Inkscape command-line renderer; no source PNG is resized. Outputs
default to the server's current versioned asset directory and synchronize the
native app icons. --output-dir exports only web previews. Artwork is transparent;
Apple launcher exports use the game's dark background because iOS needs opacity.
"""

import argparse
import copy
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


NS = "{http://www.w3.org/2000/svg}"


def opaque_icon(svg):
    icon = copy.deepcopy(svg)
    left, top, width, height = icon.attrib["viewBox"].split()
    icon.insert(0, ET.Element(NS + "rect", {
        "id": "icon-background", "x": left, "y": top,
        "width": width, "height": height, "fill": "#111619",
    }))
    return icon


def render(inkscape, source, output, size, rgb=False):
    subprocess.run([inkscape, str(source), "--export-area-page", "--export-type=png",
                    f"--export-filename={output}", f"--export-width={size}",
                    f"--export-height={size}", "--export-background-opacity=0",
                    f"--export-png-color-mode={'RGB_8' if rgb else 'RGBA_8'}"], check=True)
    print(f"{output.name}: {size}x{size} directly from SVG")


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    inkscape = shutil.which("inkscape")
    if not inkscape:
        parser.error("Inkscape is required to render the vector artwork.")

    version = re.search(r'\bversion\s*=\s*"([^"]+)"', (root / "src/main.go").read_text()).group(1)
    assets = root / "src/web/assets" / ("v" + version)
    source = assets / "favicon.svg"
    svg = ET.fromstring(source.read_text())
    output = (args.output_dir or assets).resolve()
    output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="leqra-icons-") as temporary:
        opaque_source = Path(temporary) / "opaque.svg"
        ET.register_namespace("", "http://www.w3.org/2000/svg")
        ET.ElementTree(opaque_icon(svg)).write(opaque_source, encoding="utf-8", xml_declaration=True)

        exports = [(f"icon-{size}.png", source, size) for size in (192, 512, 1024)]
        exports += [("favicon-256.png", source, 256),
                    ("apple-touch-icon.png", opaque_source, 180),
                    ("apple-touch-icon-512.png", opaque_source, 512)]
        for name, vector, size in exports:
            render(inkscape, vector, output / name, size)

        if args.output_dir is None:
            ios = root / "ios/leqra/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
            android = root / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
            render(inkscape, opaque_source, ios, 1024, rgb=True)
            shutil.copyfile(output / "icon-1024.png", android)
            for brand in (
                root / "ios/leqra/Assets.xcassets/BrandIcon.imageset/brand-icon.png",
                root / "android/app/src/main/res/drawable-nodpi/brand_icon.png",
            ):
                brand.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(output / "icon-192.png", brand)
            print("Native iOS and Android icons synchronized")


if __name__ == "__main__":
    main()
