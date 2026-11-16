#!/usr/bin/env python3
"""Render app icons from the versioned favicon.svg using Inkscape 1.2 or newer.

From the repository root: ./scripts/gen-icons.sh
Requires the Inkscape command-line renderer; no source PNG is resized. Outputs
default to the server's current versioned asset directory and synchronize the
native app icons. --output-dir exports only web previews. Maskable artwork keeps
its established 70% scale over the unscaled, opaque background.
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


def opaque_icon(svg, maskable=False):
    icon = copy.deepcopy(svg)
    background = icon.find(".//*[@id='icon-background']")
    tank = icon.find(".//*[@id='tank']")
    if background is None or tank is None:
        raise ValueError("favicon.svg requires icon-background and tank elements")
    # The operating system supplies its own corner mask. Keep the gradient
    # full-bleed rather than compositing rounded corners onto a flat color.
    background.attrib.pop("rx", None)
    background.attrib.pop("ry", None)
    if maskable:
        left, top, width, height = map(float, icon.attrib["viewBox"].split())
        cx, cy = left + width / 2, top + height / 2
        parent = next(node for node in icon.iter() if tank in list(node))
        wrapper = ET.Element(NS + "g", {
            "transform": f"translate({cx:g} {cy:g}) scale(.7) translate({-cx:g} {-cy:g})",
        })
        index = list(parent).index(tank)
        parent.remove(tank)
        parent.insert(index, wrapper)
        wrapper.append(tank)
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
        mask_source = Path(temporary) / "maskable.svg"
        ET.register_namespace("", "http://www.w3.org/2000/svg")
        ET.ElementTree(opaque_icon(svg)).write(opaque_source, encoding="utf-8", xml_declaration=True)
        ET.ElementTree(opaque_icon(svg, maskable=True)).write(mask_source, encoding="utf-8", xml_declaration=True)

        exports = [(f"icon-{size}.png", source, size) for size in (192, 512, 1024)]
        exports += [(f"icon-maskable-{size}.png", mask_source, size) for size in (512, 1024)]
        exports += [("favicon-256.png", source, 256),
                    ("apple-touch-icon.png", opaque_source, 180),
                    ("apple-touch-icon-512.png", opaque_source, 512)]
        for name, vector, size in exports:
            render(inkscape, vector, output / name, size)

        if args.output_dir is None:
            ios = root / "ios/leqra/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
            android = root / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
            render(inkscape, opaque_source, ios, 1024, rgb=True)
            shutil.copyfile(output / "icon-maskable-1024.png", android)
            print("Native iOS and Android icons synchronized")


if __name__ == "__main__":
    main()
