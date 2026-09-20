const dns = require("node:dns");
try {
  dns.setDefaultResultOrder("ipv4first");
} catch (_) {}

/** @type {import("next").NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "images.unsplash.com" },
      { protocol: "https", hostname: "ideal-poodle-813.convex.cloud" },
      { protocol: "https", hostname: "incredible-possum-462.convex.cloud" },
    ],
  },
};
module.exports = nextConfig;
