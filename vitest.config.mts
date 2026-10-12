import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

export default defineConfig({
  resolve: {
    // The admin dashboard's "@/..." import alias, so its server code can be tested from here.
    alias: { "@": fileURLToPath(new URL("./admin-dashboard/src", import.meta.url)) },
  },
  test: {
    environment: "edge-runtime",
    server: { deps: { inline: ["convex-test"] } },
    include: ["convex/**/*.test.ts", "admin-dashboard/src/**/*.test.ts"],
  },
});
