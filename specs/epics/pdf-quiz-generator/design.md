# pdf-quiz-generator — design

## 1. The template

vercel-labs/ai-sdk-preview-pdf-support @ 2216bb6 (2026-04-25; main had not
moved on 2026-11-12), Apache-2.0. A Next.js 15.5 app (React 19.2, Tailwind 3,
shadcn components, framer-motion):

- `app/(preview)/page.tsx` — the page: reads the PDF in the browser (5 MB at
  most, as a data URL), `submit`s it through `experimental_useObject` (AI SDK
  4, `ai/react`) to `/api/generate-quiz`, shows a progress bar ("Generating
  question N of 4") as the array streams in, then the quiz.
- `app/api/generate-quiz/route.ts` — `streamObject({ output: "array" })` on
  Gemini 1.5 Pro (`@ai-sdk/google`), the PDF sent as a file part, the
  template's teacher prompt, `toTextStreamResponse()`.
- `app/(preview)/actions.ts` — a server action naming the quiz from the file
  name with `generateObject` on Gemini 1.5 Flash.
- `lib/schemas.ts` — four questions, four options, an answer letter A–D.

`@vercel/kv`, `@vercel/analytics`, `@ai-sdk/anthropic` and `@ai-sdk/openai`
are dependencies nothing imports. There are no tests.

## 2. How it maps to Cloudflare

| Upstream | Here |
|---|---|
| Next.js on Vercel | `@opennextjs/cloudflare` 1.20.16 → one Worker + Static Assets; Next 15.5.15 → 15.5.29, OpenNext's floor on the 15 line, both pinned |
| Vercel's pre-rendering | The page is pre-rendered at build and served from the static-assets incremental cache; the build copies that cache into place itself (`apps/web/scripts/populate-static-assets-cache.mjs`), because `opennextjs-cloudflare populateCache local` opens wrangler's platform proxy and the AI binding — no local simulator — makes it demand a Cloudflare credential (ai-chatbot's and rag-chatbot's fix) |
| Gemini 1.5 Pro reads the PDF | Workers AI: `env.AI.toMarkdown` converts it, `@cf/zai-org/glm-4.7-flash` writes the quiz (§3) |
| `GOOGLE_GENERATIVE_AI_API_KEY` in the server's environment | An optional Orun secret, unset for the build, pushed to the Worker as a secret after it, read per request: with it, Gemini 2.5 Pro and Flash |
| `next/font/google` (Geist) | The `geist` package: `next/font/google` fails on GitHub's runners |
| "Deploy with Vercel" | The product's own "Deploy by hand" (README) |

## 3. The model and the provider

**Workers AI by default, with no key.** The Worker's `AI` binding
(`wrangler.jsonc`) needs no resource and no secret, so a bootstrap makes
quizzes from its first deploy. The PDF becomes Markdown through Workers AI's
document conversion (`env.AI.toMarkdown`); the first 200,000 characters reach
the model. The model is `@cf/zai-org/glm-4.7-flash`: a 131,072-token context,
zero data retention, function calling, no planned deprecation (GLM 5.3 Flash
has one, 2026-11-20), and nuxt-ai-editor's model.

**`createAI` from `agents/models/ai-sdk`.** `workers-ai-provider` is deprecated
and feature-frozen ("Use createAI from agents/models/ai-sdk", Cloudflare,
2026-10-21). `createAI` returns an AI SDK `ProviderV4` over the binding and
needs `ai@^7` and `@ai-sdk/provider@^4`, so the template moves from the AI SDK
4 to 7: `experimental_useObject` from `@ai-sdk/react`, the system prompt as
`instructions` (the AI SDK 7 refuses system messages in `messages`), zod 4
(`issues` for `errors`). `streamObject` is deprecated in the AI SDK 7 but
works, and its text stream is the bare array the template's
`useObject({ schema: questionsSchema })` parses — the page is unchanged.

**The streaming constraint.** `createAI` sends a structured call as
`response_format: json_schema`, and with `stream: true`; Workers AI's JSON
mode does not stream ("JSON Mode currently doesn't support streaming"; Workers
AI "rejects JSON Schema responses on streaming requests"). So
`schemaInPromptMiddleware` (`lib/ai.ts`), for a STREAMED call only, moves the
schema into the system prompt (after the template's own) and sends a text
format, and the AI SDK's `extractJsonMiddleware` strips a ```json fence while
streaming. The non-streamed title keeps JSON mode.

**Gemini, with the owner's key.** `createGoogleGenerativeAI({ apiKey })`
per request: `gemini-2.5-pro` for the quiz, the PDF sent as a file part as
upstream sent it (no conversion), `gemini-2.5-flash` for the title — the
current stable successors of the retired 1.5 Pro and Flash. Workers AI is not
called.

## 4. The route

`POST /api/generate-quiz` decodes the page's data URL and refuses, before any
model is asked: no file (400), not a data URL or not base64 (400), a type
other than `application/pdf` or bytes that are not a PDF (415), over 5 MB
(413 — the page's own limit), a conversion with no text (422), and no Workers
AI binding with no key (503, `next dev`). `maxDuration = 60` is kept; a Worker
has no wall-clock limit while its client is connected, and its CPU limit
(10 ms on Free) is risk PQ-C.

## 5. The repository and the build

The Cirrus conventions, from microcms-blog's current main (Next on OpenNext,
an optional per-request secret, a test-only Worker entry): `apps/web`
(`cloudflare-workers-assets-turbo`, `lane: isolated`), `tests/web`
(vitest), `tooling/`, no infra component — Workers AI provisions nothing.
Two phases, one landing (`01-product`, then `02-docs`). The smoke asks the
page for its upload card and the route for its 400 to an empty upload: the
Worker's own code, and no model spent.

## 6. Testing without a model

Neither Workers AI (no local mode) nor Gemini (a key, the network) can be
called offline. The product carries no seam for it:

- `tests/web` runs the real route with `getCloudflareContext()` answering a
  fake binding (`toMarkdown` reads the PDF's `(…) Tj` text; `run` answers raw
  Responses in Workers AI's shapes, the quiz fenced and chunked), the page in
  jsdom against a chunked stream, and the model choice and middleware.
- The e2e serves the staged build through its own Worker entry
  (`testing/lib/e2e-worker.mjs`), which hands the Worker an in-process
  Workers AI and wraps the global fetch to answer Google's API host before
  the Worker's modules load; the `ai` block leaves the e2e's copy of
  `wrangler.jsonc` only.

What that proves is the app's half. Whether a real model answers well is risk
PQ-B.

## 7. Out of scope

Sign-in or rate limiting (the template has none; risk PQ-E), storing quizzes
(the template keeps none; `@vercel/kv` was never used), OCR of scanned PDFs
beyond what `toMarkdown` does, and Gemini through AI Gateway.

## 8. The alternatives rejected

- **`workers-ai-provider` on the AI SDK 4**: keeps upstream's SDK, but the
  provider is deprecated and frozen.
- **Workers AI's JSON mode for the quiz**: no streaming — the progress bar
  would jump from 0 to 100.
- **A tool call for the structured answer** (Think's approach): streams, but
  the page would need a different stream than `useObject` reads.
- **Gemini as the default**: needs a key at bootstrap, which no platform
  connection mints.
