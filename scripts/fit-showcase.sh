#!/bin/sh
set -eu
# macOS: use 100% Chrome zoom, undock DevTools, and bring the showcase window forward.
# Enable View > Developer > Allow JavaScript from Apple Events in Chrome.
exec osascript <<'APPLESCRIPT'
tell application "Google Chrome"
 if (count of windows) is 0 then error "Open the generated showcase in Chrome first."
 set showcaseWindow to front window
 set fittedBounds to execute active tab of showcaseWindow javascript "
(() => {
 const image = document.querySelector('img[data-leqra-showcase]');
 if (!image?.naturalWidth) throw Error('Open the generated showcase in the front Chrome window first.');
 const ratio = image.naturalWidth / image.naturalHeight;
 const frameWidth = outerWidth - innerWidth, frameHeight = outerHeight - innerHeight;
 const width = Math.floor(Math.min(screen.availWidth - frameWidth, (screen.availHeight - frameHeight) * ratio));
 const height = Math.ceil(width / ratio);
 const windowWidth = width + frameWidth, windowHeight = height + frameHeight;
 const left = screen.availLeft + Math.floor((screen.availWidth - windowWidth) / 2);
 const top = screen.availTop + Math.floor((screen.availHeight - windowHeight) / 2);
 return [left, top, left + windowWidth, top + windowHeight];
})()
"
 if fittedBounds is missing value then error "Reload the generated showcase and bring its Chrome window to the front, then try again."
 set bounds of showcaseWindow to fittedBounds
end tell
APPLESCRIPT
