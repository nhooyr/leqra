"""Icon export contracts with an isolated SVG and a renderer stub."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
NS = "{http://www.w3.org/2000/svg}"
SOURCE = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
<defs><linearGradient id="tile"><stop stop-color="#bdc4ff"/>
<stop offset="1" stop-color="#8295ee"/></linearGradient></defs>
<rect id="icon-background" width="64" height="64" rx="14" fill="url(#tile)"/>
<g id="tank"><rect x="20" y="20" width="24" height="24" fill="#ffffff"/></g>
</svg>"""


class IconGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="leqra icon exports ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        shutil.copy2(ROOT / "scripts/render-icons.py", scripts)
        self.script = scripts / "render-icons.py"
        (self.root / "src").mkdir()
        (self.root / "src/main.go").write_text('const version = "1.2.3"\n')
        self.assets = self.root / "src/web/assets/v1.2.3"
        self.assets.mkdir(parents=True)
        (self.assets / "favicon.svg").write_text(SOURCE)
        self.ios = self.root / "ios/leqra/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        self.android = self.root / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
        for path in (self.ios, self.android):
            path.parent.mkdir(parents=True)
            path.write_bytes(b"original native icon")
        commands = self.root / "commands"
        commands.mkdir()
        renderer = commands / "inkscape"
        renderer.write_text(f"#!{sys.executable}\n" + """
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
svg = Path(args[0]).read_text()
output = next(a.split('=', 1)[1] for a in args if a.startswith('--export-filename='))
Path(output).write_text(svg)
with open(os.environ['ICON_EXPORT_LOG'], 'a') as log:
    log.write(json.dumps({'args': args, 'svg': svg, 'output': output}) + '\\n')
""")
        renderer.chmod(0o755)
        self.log = self.root / "exports.jsonl"
        self.env = {**os.environ, "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                    "ICON_EXPORT_LOG": str(self.log)}

    def run_generator(self, *args):
        result = subprocess.run([sys.executable, str(self.script), *args], cwd=self.root,
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def assert_opaque_background(self, export):
        svg = ET.fromstring(export["svg"])
        background = svg.find(".//*[@id='icon-background']")
        self.assertIsNotNone(background)
        self.assertNotIn("rx", background.attrib)
        self.assertNotIn("ry", background.attrib)
        self.assertEqual(background.attrib["fill"], "url(#tile)")
        self.assertIn(background, list(svg), "the background must remain unscaled")
        return svg

    def test_preview_preserves_native_icons_and_scales_only_maskable_foreground(self):
        output = self.root / "web previews"
        exports = self.run_generator("--output-dir", str(output))
        self.assertEqual(len(exports), 8)
        for path in (self.ios, self.android):
            self.assertEqual(path.read_bytes(), b"original native icon")
        for export in exports:
            name = Path(export["output"]).name
            if "maskable" in name:
                svg = self.assert_opaque_background(export)
                tank = svg.find(".//*[@id='tank']")
                wrapper = next(node for node in svg.iter() if tank in list(node))
                self.assertEqual(wrapper.attrib["transform"], "translate(32 32) scale(.7) translate(-32 -32)")
            elif name.startswith("apple-touch"):
                self.assert_opaque_background(export)
            else:
                self.assertEqual(ET.fromstring(export["svg"]).find(".//*[@id='icon-background']").get("rx"), "14")

    def test_default_syncs_rgb_ios_and_identical_maskable_android(self):
        exports = self.run_generator()
        self.assertEqual(len(exports), 9)
        ios = next(e for e in exports if Path(e["output"]).resolve() == self.ios.resolve())
        self.assertIn("--export-png-color-mode=RGB_8", ios["args"])
        self.assertIn("--export-width=1024", ios["args"])
        self.assert_opaque_background(ios)
        self.assertEqual(self.android.read_bytes(), (self.assets / "icon-maskable-1024.png").read_bytes())
        self.assertEqual((self.assets / "favicon.svg").read_text(), SOURCE)


if __name__ == "__main__":
    unittest.main()
