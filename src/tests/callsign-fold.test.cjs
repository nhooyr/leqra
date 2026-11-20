"use strict"
const { extractFunction } = require("./source_helpers.cjs")
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  vm = require("node:vm"),
  { createHash } = require("node:crypto"),
  { readFileSync } = require("node:fs"),
  path = require("node:path"),
  { assetPath } = require("./web_assets.cjs")
const fixture = JSON.parse(readFileSync(path.join(__dirname, "fixtures/callsign-fold.json"), "utf8"))
const source = readFileSync(assetPath("callsigns.js"), "utf8")
    .split("// BEGIN GENERATED CALLSIGN FOLD\n")[1]
    .split("// END GENERATED CALLSIGN FOLD")[0],
  context = {}
vm.createContext(context)
vm.runInContext(source, context)

test("client callsign folding preserves exact Go Unicode classes", () => {
  for (const [name, expected] of fixture.cases) assert.equal(context.canonical(name), expected, name)
  assert.equal(context.canonical("Σnow"), context.canonical("ςNOW"))
  assert.notEqual(context.canonical("ß"), context.canonical("SS"))
  assert.notEqual(context.canonical("ı"), context.canonical("i"))
  assert.notEqual(context.canonical("ﬃ"), context.canonical("FFI"))
})

test("client folding matches the Go-generated digest over every Unicode scalar", () => {
  const hash = createHash("sha256"),
    pair = Buffer.alloc(8)
  for (let point = 0; point <= 0x10ffff; point++) {
    if (point >= 0xd800 && point <= 0xdfff) continue
    const folded = context.canonical(String.fromCodePoint(point))
    pair.writeUInt32BE(point, 0)
    pair.writeUInt32BE(folded.codePointAt(0), 4)
    hash.update(pair)
  }
  assert.equal(hash.digest("hex"), fixture.scalarSHA256)
})

test("web callsign cleanup matches decimal-number and scalar-length rules", () => {
  const game = readFileSync(assetPath("game.js"), "utf8"),
    declaration = extractFunction(game, "cleanPilotName")
  const clean = {}
  vm.createContext(clean)
  vm.runInContext(declaration, clean)
  assert.equal(clean.cleanPilotName("A²Ⅳ٣४𝟡"), "A٣४𝟡")
  assert.equal(clean.cleanPilotName("𝟡".repeat(17)), "𝟡".repeat(16))
})
