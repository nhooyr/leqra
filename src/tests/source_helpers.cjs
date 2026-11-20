"use strict"

const { parse } = require("acorn")
const sources = new Map()

function indexSource(source) {
  if (sources.has(source)) return sources.get(source)
  const result = { functions: new Map(), declarations: new Map(), statements: [], tokens: [] }
  function visit(node) {
    if (!node || typeof node !== "object") return
    if (node.type === "FunctionDeclaration" && node.id && !result.functions.has(node.id.name)) {
      result.functions.set(node.id.name, node)
    }
    if (node.type === "VariableDeclaration") {
      for (const declaration of node.declarations) {
        if (declaration.id.type === "Identifier" && !result.declarations.has(declaration.id.name)) {
          result.declarations.set(declaration.id.name, node)
        }
      }
    }
    if (node.type?.endsWith("Statement") || node.type === "VariableDeclaration") result.statements.push(node)
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit)
      else if (value && typeof value === "object") visit(value)
    }
  }
  visit(parse(source, { ecmaVersion: "latest", sourceType: "script", onToken: result.tokens }))
  sources.set(source, result)
  return result
}

function extractFunction(source, name) {
  const node = indexSource(source).functions.get(name)
  if (!node) throw new Error("Missing function: " + name)
  return source.slice(node.start, node.end)
}

function functionEnd(source, start) {
  const node = [...indexSource(source).functions.values()].find((node) => node.start === start)
  if (!node) throw new Error("Missing function at: " + start)
  return node.end
}

function extractDeclaration(source, name) {
  const node = indexSource(source).declarations.get(name)
  if (!node) throw new Error("Missing declaration: " + name)
  const declaration = source.slice(node.start, node.end)
  return declaration.endsWith(";") ? declaration : declaration + ";"
}

function extractInitializer(source, name) {
  const node = indexSource(source).declarations.get(name)
  const declaration = node?.declarations.find((declaration) => declaration.id.name === name)
  if (!declaration?.init) throw new Error("Missing initializer: " + name)
  return source.slice(declaration.init.start, declaration.init.end)
}

function sourceRange(source, marker, from = 0) {
  const exact = source.indexOf(marker, from)
  if (exact >= 0 && !(/[\w$]/.test(marker.at(-1)) && /[\w$]/.test(source[exact + marker.length] || ""))) {
    return { start: exact, end: exact + marker.length }
  }
  const expected = []
  try {
    const { tokenizer } = require("acorn")
    const input = tokenizer(marker, { ecmaVersion: "latest" })
    for (let token = input.getToken(); token.type.label !== "eof"; token = input.getToken()) {
      if (token.type.label !== ";") expected.push(token)
    }
  } catch {
    return null
  }
  if (!expected.length) return null
  const tokens = indexSource(source).tokens.filter((token) => token.type.label !== ";")
  for (let index = 0; index <= tokens.length - expected.length; index++) {
    if (tokens[index].start < from) continue
    if (
      expected.every(
        (token, offset) =>
          token.type.label === tokens[index + offset].type.label &&
          JSON.stringify(token.value) === JSON.stringify(tokens[index + offset].value),
      )
    ) {
      return { start: tokens[index].start, end: tokens[index + expected.length - 1].end }
    }
  }
  return null
}

function sourceIndex(source, marker, from = 0) {
  return sourceRange(source, marker, from)?.start ?? -1
}

function extractStatement(source, marker) {
  const start = sourceIndex(source, marker.trim())
  const node = indexSource(source).statements.find((node) => node.start === start)
  if (!node) throw new Error("Missing statement: " + marker)
  return source.slice(node.start, node.end)
}

function replaceSource(source, marker, replacement) {
  const range = sourceRange(source, marker)
  if (!range) throw new Error("Missing source: " + marker)
  return source.slice(0, range.start) + replacement + source.slice(range.end)
}

module.exports = {
  extractFunction,
  functionEnd,
  extractDeclaration,
  extractInitializer,
  extractStatement,
  sourceIndex,
  replaceSource,
}
