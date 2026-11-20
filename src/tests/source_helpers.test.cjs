"use strict"
const { test } = require("node:test")
const assert = require("node:assert/strict")
const vm = require("node:vm")
const {
  extractFunction,
  functionEnd,
  extractDeclaration,
  extractInitializer,
  extractStatement,
  sourceIndex,
  replaceSource,
} = require("./source_helpers.cjs")

test("function extraction accepts compact and indented source without running it", () => {
  for (const source of [
    "function wanted(value={x:'}'}){return `${value.x}:${(() => '{')()}`;}\nfunction next(){}",
    "(() => {\n  function wanted(value = { x: '}' }) {\n    return `${value.x}:${(() => '{')()}`\n  }\n  function next() {}\n})()",
  ]) {
    const text = extractFunction(source, "wanted")
    assert.equal(vm.runInNewContext("(" + text + ")")(), "}:{")
    assert.ok(!text.includes("function next"))
    assert.equal(extractFunction(source, "wanted"), text)
  }
})

test("function extraction preserves async and ignores braces inside comments and regexes", async () => {
  const source =
    "async function wanted() {\n  // }\n  return /}/.test(await Promise.resolve('}'))\n}\nfunction next() {}"
  assert.equal(await vm.runInNewContext("(" + extractFunction(source, "wanted") + ")")(), true)
  assert.throws(() => extractFunction(source, "absent"), /Missing function/)
  assert.throws(() => extractFunction("function unfinished() {", "unfinished"), SyntaxError)
})

test("declarations retain their entire initializer and can be evaluated consecutively", () => {
  const source = 'const first = ["}", 2].map(value => value)\nconst second = { first }\n'
  const context = {}
  vm.runInNewContext(
    extractDeclaration(source, "first") +
      extractDeclaration(source, "second") +
      "this.value = second.first[1]",
    context,
  )
  assert.equal(context.value, 2)
  assert.equal(extractInitializer(source, "second"), "{ first }")
  assert.throws(() => extractDeclaration(source, "missing"), /Missing declaration/)
})

test("source markers and replacements ignore formatting but preserve token boundaries", () => {
  const source = 'const level = "high"\nfunction next() { return level }\n'
  assert.equal(sourceIndex(source, "const level='high';"), 0)
  const start = sourceIndex(source, "function next(")
  assert.equal(source.slice(start, functionEnd(source, start)), extractFunction(source, "next"))
  assert.equal(sourceIndex(source, "level", 6), source.indexOf("level", 6))
  assert.equal(sourceIndex(source, "const lev"), -1)
  assert.equal(
    replaceSource(source, "const level='high';", 'const level = "low"'),
    source.replace('"high"', '"low"'),
  )
  assert.throws(() => replaceSource(source, "const missing = 1", ""), /Missing source/)
})

test("statement extraction keeps multiline event bindings without adjoining statements", () => {
  const source = 'function init() {\n window.listen("event", () => { run() })\n after()\n}'
  assert.equal(extractStatement(source, "window.listen('event'"), 'window.listen("event", () => { run() })')
  assert.throws(() => extractStatement(source, "absent()"), /Missing statement/)
})
