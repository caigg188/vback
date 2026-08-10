import { defineConfig } from "vite";
import preact from "@preact/preset-vite";
import { resolve } from "node:path";

export default defineConfig({
  plugins: [preact()],
  build: {
    outDir: resolve(__dirname, "../internal/webui/dist"),
    emptyOutDir: true,
    sourcemap: false,
    target: "es2022",
  },
  server: {
    proxy: {
      "/api": "http://127.0.0.1:9898",
    },
  },
});
