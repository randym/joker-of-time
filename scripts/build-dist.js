"use strict";

const path = require("path");
const fs = require("fs");

const rootDir = path.resolve(__dirname, "..");
const distDir = process.env.OUT_DIR
  ? path.resolve(rootDir, process.env.OUT_DIR)
  : path.join(rootDir, ".dev");
const srcDir = path.join(rootDir, "src");

const tryRequire = (id) => {
  try {
    return require(id);
  } catch (e) {
    if (e.code === "MODULE_NOT_FOUND") {
      throw new Error(
        `Missing dependency: ${id}. Run from repo root: yarn install`
      );
    }
    throw e;
  }
};
const esbuild = tryRequire("esbuild");
const { stripLogFromSource } = require("./strip-log-plugin");

const stripLogPlugin = {
  name: "strip-log",
  setup(build) {
    build.onLoad({ filter: /\.ts$/ }, async (args) => {
      const contents = fs.readFileSync(args.path, "utf8");
      const result = stripLogFromSource(contents, args.path);
      if (!result || !result.contents) return null;
      return { contents: result.contents, loader: "ts" };
    });
  },
};

const keepLog = process.env.KEEP_LOG === "1" || process.env.JOT_DEV === "1";

async function main() {
  if (!fs.existsSync(distDir)) fs.mkdirSync(distDir, { recursive: true });

  await esbuild.build({
    entryPoints: [path.join(srcDir, "cli.ts")],
    bundle: true,
    platform: "node",
    target: "node18",
    format: "cjs",
    outfile: path.join(distDir, "cli.js"),
    minify: !keepLog,
    sourcemap: false,
    external: ["playwright"],
    plugins: keepLog ? [] : [stripLogPlugin],
  });

  for (const name of fs.readdirSync(distDir)) {
    if (name !== "cli.js" && (name.endsWith(".js") || name === ".esbuild-done")) {
      fs.unlinkSync(path.join(distDir, name));
    }
  }

  const label = path.relative(rootDir, path.join(distDir, "cli.js"));
  console.log(keepLog ? `Dist build done: ${label} (dev, logging enabled)` : `Dist build done: ${label} (log stripped, minified)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
