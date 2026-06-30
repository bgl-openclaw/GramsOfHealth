import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

export default defineConfig({
  resolve: {
    alias: {
      // Run tests against the engine source directly, no build step needed.
      "@goh/engine": fileURLToPath(new URL("./packages/engine/src/index.ts", import.meta.url)),
    },
  },
  test: {
    include: ["tests/**/*.test.ts"],
  },
});
