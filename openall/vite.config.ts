import react from "@vitejs/plugin-react";
import { defineConfig, loadEnv } from "vite";

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  // Load .env so we can inject keys into proxy headers.
  const env = loadEnv(mode, process.cwd(), "");

  /* ------------------------------------------------------------------ */
  /*  Provider proxy targets                                             */
  /* ------------------------------------------------------------------ */
  const proxyTargets: Record<string, { target: string; envKey: string }> = {
    openrouter: {
      target: "https://openrouter.ai/api/v1",
      envKey: "OPENROUTER_API_KEY",
    },
    groq: {
      target: "https://api.groq.com/openai/v1",
      envKey: "GROQ_API_KEY",
    },
    google: {
      target: "https://generativelanguage.googleapis.com/v1beta/openai",
      envKey: "GOOGLE_AI_KEY",
    },
    mistral: {
      target: "https://api.mistral.ai/v1",
      envKey: "MISTRAL_API_KEY",
    },
    ollama: {
      target: "http://localhost:11434/v1",
      envKey: "OLLAMA_HOST",
    },
    prototype: {
      target: "http://localhost:3001",
      envKey: "",
    },
    lively: {
      target: "http://localhost:3001",
      envKey: "",
    },
  };

  /* ------------------------------------------------------------------ */
  /*  Build Vite proxy entries                                           */
  /* ------------------------------------------------------------------ */
  const proxy: Record<string, object> = {};

  for (const [id, { target, envKey }] of Object.entries(proxyTargets)) {
    const key = envKey ? env[envKey] : "";
    const useUpstream = Boolean(key || id === "ollama");
    const effectiveTarget = useUpstream ? target : "http://localhost:3001";

    proxy[`/api/llm/${id}`] = {
      target: effectiveTarget,
      changeOrigin: true,
      rewrite: (path: string) =>
        useUpstream ? path.replace(new RegExp(`^/api/llm/${id}`), "") : path,
      configure: (proxyInstance: { on: (event: string, handler: (...args: unknown[]) => void) => void }) => {
        proxyInstance.on(
          "proxyReq",
          (...args: unknown[]) => {
            const proxyReq = args[0] as { setHeader?: (name: string, value: string) => void } | undefined;
            if (key && proxyReq?.setHeader) {
              proxyReq.setHeader("Authorization", `Bearer ${key}`);
            }
          },
        );
      },
    };
  }

  // Unified prototype backend endpoints
  proxy["/api/providers"] = {
    target: "http://localhost:3001",
    changeOrigin: true,
  };
  proxy["/api/providers/keys"] = {
    target: "http://localhost:3001",
    changeOrigin: true,
  };
  proxy["/api/chat/completions"] = {
    target: "http://localhost:3001",
    changeOrigin: true,
  };
  proxy["/api/models"] = {
    target: "http://localhost:3001",
    changeOrigin: true,
  };
  proxy["/api/models/refresh"] = {
    target: "http://localhost:3001",
    changeOrigin: true,
  };
  proxy["/api/health"] = {
    target: "http://localhost:3001",
    changeOrigin: true,
  };

  return {
    plugins: [react()],
    server: { proxy },
  };
});
