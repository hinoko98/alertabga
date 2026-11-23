import type { NextConfig } from "next";

// En Vercel la API es la función Python api/index.py; en local (dev o `npm run preview`) es uvicorn :8000.
const onVercel = Boolean(process.env.VERCEL);

const nextConfig: NextConfig = {
  // Permite la recarga en vivo (HMR) al abrir el panel por IP local en vez de localhost.
  allowedDevOrigins: ["127.0.0.1", "192.168.56.1"],
  turbopack: {
    rules: {
      "*.css": { loaders: ["@tailwindcss/turbopack"], as: "*.css" },
    },
  },
  async rewrites() {
    return [
      {
        source: "/api/py/:path*",
        destination: onVercel ? "/api/" : "http://127.0.0.1:8000/api/py/:path*",
      },
    ];
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
        ],
      },
    ];
  },
};

export default nextConfig;
