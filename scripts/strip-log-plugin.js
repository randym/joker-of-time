"use strict";

const path = require("path");
const parser = require("@babel/parser");
const traverse = require("@babel/traverse").default;
const generate = require("@babel/generator").default;
const t = require("@babel/types");

/**
 * Returns transformed TypeScript source with log import and all log.info/error/debug
 * call statements removed. Used by esbuild onLoad so the dist bundle has no logging.
 */
function stripLogFromSource(code, filePath) {
  const isLogModule =
    path.basename(filePath, path.extname(filePath)) === "log";
  if (isLogModule) {
    return {
      contents:
        "export function info(){}\nexport function error(){}\nexport function debug(){}",
    };
  }

  let ast;
  try {
    ast = parser.parse(code, {
      sourceType: "module",
      plugins: ["typescript"],
    });
  } catch (err) {
    return null;
  }

  const logBindingNames = new Set();

  traverse(ast, {
    ImportDeclaration(ip) {
      const src = ip.node.source.value;
      if (src === "./log" || src === "log") {
        for (const spec of ip.node.specifiers) {
          if (t.isImportNamespaceSpecifier(spec)) {
            logBindingNames.add(spec.local.name);
          } else if (t.isImportDefaultSpecifier(spec)) {
            logBindingNames.add(spec.local.name);
          } else if (t.isImportSpecifier(spec)) {
            logBindingNames.add(spec.local.name);
          }
        }
        ip.remove();
      }
    },
  });

  traverse(ast, {
    ExpressionStatement(exprPath) {
      const expr = exprPath.node.expression;
      if (!t.isCallExpression(expr)) return;
      const callee = expr.callee;
      if (!t.isMemberExpression(callee)) return;
      const obj = callee.object;
      const prop = callee.property;
      if (!t.isIdentifier(obj)) return;
      if (!logBindingNames.has(obj.name)) return;
      if (!t.isIdentifier(prop) || !["info", "error", "debug"].includes(prop.name)) return;
      exprPath.remove();
    },
  });

  const out = generate(ast, { retainLines: false, compact: false });
  return { contents: out.code };
}

module.exports = { stripLogFromSource };
