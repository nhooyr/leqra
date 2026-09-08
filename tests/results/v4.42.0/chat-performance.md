# Chat history timestamp formatting

The chat history renderer previously called `Date.toLocaleTimeString` with
locale options for every message. That repeats locale-formatter setup when
opening or replacing a conversation of up to 120 messages.

A history render now creates one `Intl.DateTimeFormat` and shares it across that
batch. A fresh formatter is created on every nonempty refresh, so device locale
and timezone defaults are resolved again. Live single-message appends retain
their existing native formatting path. Empty histories skip formatter setup.
Message order, text, labels, dates, scrolling, and delivery state are unchanged.

## Measurement

Baseline: `f91c819`, v4.41.0. Node.js v24.19.0. The fixture executes the production
`renderActiveChat`, `combinedChatMessages`, and `renderChatMessage` functions
with native date/Intl formatting and a lightweight DOM stand-in. Each result is
the median of seven samples of 40 full history renders, after three warm-ups.

| Messages | Before, ms/render | After, ms/render | Relative speed |
| --- | ---: | ---: | ---: |
| 20 | 0.9711 | 0.1620 | 6.0× |
| 120 | 6.3950 | 0.8430 | 7.6× |

This is the JavaScript history-building operation, excluding browser layout,
paint, scrolling cost, networking, and game simulation. It is not a game-FPS or
physical-device measurement. Empty renders remain in the microsecond range
(0.0020 ms before, 0.0026 ms after); timing varies on a shared machine.

## Verification

All 17 focused chat tests passed. Four new tests verify exact native timestamp
output and message order, one formatter per batch, fresh live-message
formatting, device timezone changes between openings, and the empty-history
path. The existing tests cover bounded retention, channel isolation, scroll
position, reconnect recovery, recipient stability, and draft preservation.
JavaScript syntax and `git diff --check` passed.

Reproduce the benchmark using this revision's fixture against each source:

```sh
git show f91c819:web/game.js > /tmp/leqra-v441-game.js
LEQRA_CHAT_SOURCE=/tmp/leqra-v441-game.js node tests/chat442.bench.cjs
node tests/chat442.bench.cjs
node --test --test-reporter=tap tests/chat429.test.cjs tests/chat442.test.cjs
```

Raw before/after timings and test output are adjacent to this report.
