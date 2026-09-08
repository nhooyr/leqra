#!/usr/bin/env python3
"""Render crisp app icons from web/favicon.svg using Inkscape 1.2 or newer.

Run from any directory: python3 scripts/render-icons.py
Requires the Inkscape command-line renderer; no source PNG is resized. Outputs
default to the server's current versioned asset directory. The maskable version
keeps the established 70% artwork scale on an opaque, full-bleed background.
"""

import argparse
import copy
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    inkscape = shutil.which("inkscape")
    if not inkscape:
        parser.error("Inkscape is required to render the vector artwork.")

    source = root / "web/favicon.svg"
    svg = ET.fromstring(source.read_text())
    ns = "{http://www.w3.org/2000/svg}"
    styles = " ".join(node.text or "" for node in svg.iter(ns + "style"))
    background = re.search(r"\.bg\s*\{\s*fill:\s*(#[0-9a-fA-F]+)", styles).group(1)
    version = re.search(r'\bversion\s*=\s*"([^"]+)"', (root / "main.go").read_text()).group(1)
    output = (args.output_dir or root / "web/assets" / ("v" + version)).resolve()
    output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="leqra-icons-") as temporary:
        # Embed the original SVG unchanged at the same 70% scale as the existing
        # maskable icon. Render its transparent corners onto the dark background.
        mask = ET.Element(ns + "svg", {"viewBox": svg.attrib["viewBox"]})
        left, top, width, height = map(float, svg.attrib["viewBox"].split())
        ET.SubElement(mask, ns + "rect", {"x": str(left), "y": str(top),
                     "width": str(width), "height": str(height), "fill": background})
        artwork = copy.deepcopy(svg)
        artwork.attrib.update(x=str(left + width * .15), y=str(top + height * .15),
                              width=str(width * .7), height=str(height * .7))
        mask.append(artwork)
        mask_source = Path(temporary) / "maskable.svg"
        ET.register_namespace("", "http://www.w3.org/2000/svg")
        ET.ElementTree(mask).write(mask_source, encoding="utf-8", xml_declaration=True)

        exports = [(f"icon-{size}.png", source, size, False) for size in (192, 512, 1024)]
        exports += [(f"icon-maskable-{size}.png", mask_source, size, True) for size in (512, 1024)]
        exports += [("favicon-256.png", source, 256, False),
                    ("apple-touch-icon.png", source, 180, True),
                    ("apple-touch-icon-512.png", source, 512, True)]
        for name, vector, size, opaque in exports:
            subprocess.run([inkscape, str(vector), "--export-area-page", "--export-type=png",
                            f"--export-filename={output / name}", f"--export-width={size}",
                            f"--export-height={size}", f"--export-background={background}",
                            f"--export-background-opacity={1 if opaque else 0}"], check=True)
            print(f"{name}: {size}x{size} directly from SVG")


if __name__ == "__main__":
    main()
