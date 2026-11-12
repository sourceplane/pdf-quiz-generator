# pdf-quiz-generator — implementation status

| Milestone | State | Landed |
|---|---|---|
| PQ0 — the spec | ✅ | the repository's first commit, PQ-1 |
| PQ1 — the quiz on Workers | ✅ | PQ-2 |
| PQ2 — a baseline | ✅ | PQ-3, tagged `baseline-v1` |

Upstream: vercel-labs/ai-sdk-preview-pdf-support @ `2216bb67fb01a1ebb89a6352ba09ee439a5eecb5`.
Licence: Apache-2.0, as the root `LICENSE` reads ("Copyright 2024 Vercel, Inc.
Licensed under the Apache License, Version 2.0 …"; GitHub shows NOASSERTION;
package.json has no `license`). It ships as `apps/web/LICENSE`.

## Departures from the upstream template

1. **Next** 15.5.15 → **15.5.29**, with **@opennextjs/cloudflare 1.20.16** (its
   floor on the 15 line), both pinned.
2. **The model**: Gemini 1.5 Pro and Flash (retired) → **Workers AI** through
   the Worker's `AI` binding by default: `env.AI.toMarkdown` converts the PDF,
   `@cf/zai-org/glm-4.7-flash` writes the quiz and the title. With the owner's
   optional `GOOGLE_GENERATIVE_AI_API_KEY`, **Gemini 2.5 Pro and Flash**, the
   PDF sent as upstream sent it.
3. **The AI SDK** 4 → **7** (`ai` 7.0.170): required by `createAI` from
   `agents/models/ai-sdk` (0.31.0), Cloudflare's provider, since
   `workers-ai-provider` is deprecated. With it: `experimental_useObject` from
   `@ai-sdk/react` 4.0.174 (typed `experimental_useObject<typeof
   questionsSchema>`: upstream's `initialValue: undefined` made the result
   `never`), the system prompt as `instructions`, `@ai-sdk/google` 1 → 4,
   **zod** 3 → 4 (`res.error.issues` for `errors`). `streamObject` and
   `generateObject` kept (deprecated in 7, working).
4. **Streaming on Workers AI**: the streamed quiz's JSON schema rides in the
   system prompt with no response format (`schemaInPromptMiddleware`), and
   `extractJsonMiddleware` strips a code fence; the title keeps JSON mode.
5. **The route** checks the upload before any model: 400 (no file, not a data
   URL, not base64, not JSON), 415 (not a PDF), 413 (over 5 MB), 422 (no
   text), 503 (no binding and no key, `next dev`). Upstream checked only in
   the browser and threw on a missing file.
6. **The title action** returns "Quiz" when the model fails (upstream's
   rejection left the page's promise unhandled; the page showed "Quiz" either
   way).
7. **The site seam** (`app/site.ts`): the title and heading read `SITE_NAME`
   ("PDF Quiz Generator", upstream's heading; the tab said "PDF Support
   Preview"); "View Source Code" and the Vercel deploy button link the
   product's own repository and its "Deploy by hand" (the button now "Deploy
   your own", a Cloud icon); `metadataBase` is the environment's origin.
8. **The description** names Cloudflare Workers AI and ai-sdk.dev where it
   named Google's Gemini Pro and sdk.vercel.ai.
9. **Fonts**: `next/font/google` (Geist) → the `geist` package.
10. **Not carried**: `@vercel/kv`, `@vercel/analytics`, `@ai-sdk/anthropic`,
    `@ai-sdk/openai` (nothing imported them); the README's deploy instructions.
11. **Lint**: the template's `.eslintrc.json` (`next/core-web-vitals`) as an
    ESLint 9 flat config through FlatCompat; `next lint` kept.
12. **The build** copies the static-assets cache itself
    (`scripts/populate-static-assets-cache.mjs`) instead of `opennextjs-cloudflare
    populateCache local`, which asks for a Cloudflare credential once an AI
    binding is declared.
13. **Workspace**: pnpm 10.12.1, the workspace's lockfile seeded from
    upstream's (its React, Radix, framer-motion, lucide, Tailwind and sonner
    resolutions kept); `next.config.mjs` gains `output: "standalone"`,
    `outputFileTracingRoot`, `images.unoptimized` and the preview origins;
    `tsconfig.json` excludes the OpenNext config and build output.
14. **Tests**: the template ships none; `tests/web` adds them. Its tsconfig
    checks the app files it imports with the app's own settings
    (`noUncheckedIndexedAccess` off: upstream's page and quiz index arrays
    they have just checked).

## Verified

- The spike, in a scratch copy: the
  route under `wrangler dev` with in-process stand-ins — 5 chunks over 1.06 s,
  the first whole question at 0.34 s, four valid questions from the PDF's
  lines; the Gemini path with the key, the PDF and JSON mode; the title.
- The Worker: 7,022 KiB raw, about 1,468 KiB gzipped — Workers Free's 3 MiB.
- Not verified: a real model's answer (risk PQ-B), a live deploy (PQ-A).
