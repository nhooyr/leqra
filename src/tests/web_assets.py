"""Locate the browser assets used by the selected shell."""

import re


def asset_directory(web):
    html = (web / "index.html").read_text()
    match = re.search(r'\bsrc="(assets/v[^/"]+)/game\.js"', html)
    # Historical comparison runners also accept archived, unversioned shells.
    return web / match.group(1) if match else web
