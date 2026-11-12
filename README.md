# pdf-quiz-generator

Vercel's [PDF to Quiz Generator](https://github.com/vercel-labs/ai-sdk-preview-pdf-support)
— the AI SDK's PDF example: upload a PDF and get a four-question
multiple-choice quiz about it, each question shown as it streams in, then the
quiz, its score and its review — running on **Cloudflare Workers + Static
Assets** through [`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), deployed by
[Orun](https://github.com/sourceplane/orun) to stage and prod on every merge.
Packaging it as an Orun baseline is the next milestone (PQ2). It makes quizzes from its first deploy, on Workers AI, with no
model key.

The template's page and components are the code. What the port adds is the
Workers build, the monorepo wrapper, a test package and the deploy contract;
what it changes is what Workers, and time, force:

- **The model:** the template sent the PDF to Google's Gemini 1.5 Pro, now
  retired. Here Workers AI turns the PDF into Markdown (`env.AI.toMarkdown`)
  and writes the quiz (`@cf/zai-org/glm-4.7-flash`) through the Worker's own
  `AI` binding — no key. With the owner's optional Google key, the quiz runs
  on Gemini instead (`gemini-2.5-pro`, the title on `gemini-2.5-flash`), which
  reads the PDF itself, as upstream did.
- **The provider:** `createAI` from `agents/models/ai-sdk`, Cloudflare's
  provider for Workers AI (it replaced the deprecated `workers-ai-provider`),
  which needs the AI SDK 7 — so the template's AI SDK 4 moves to 7, its
  `experimental_useObject` to `@ai-sdk/react`, its system prompt to
  `instructions` and zod to 4.
- **Streaming:** Workers AI refuses a JSON-schema response format on a
  streamed request, so the streamed quiz carries its schema in the prompt and
  its answer is unfenced on the way (`lib/ai.ts`); the title, not streamed,
  keeps JSON mode. See
[`specs/epics/pdf-quiz-generator`](specs/epics/pdf-quiz-generator/README.md) for the
design, the milestones and the as-built status.

## What is here (the site)

| Surface | Where |
|---|---|
| The page: upload, streamed progress, the quiz, its score and review (the template's) | `apps/web/app/(preview)/page.tsx`, `apps/web/components` |
| The quiz route: the PDF decoded and checked, converted, the quiz streamed | `apps/web/app/api/generate-quiz/route.ts`, `apps/web/lib/pdf.ts` |
| The quiz's title (a server action) | `apps/web/app/(preview)/actions.ts` |
| The models: Workers AI over the binding, or Gemini with the owner's key, and the schema-in-prompt middleware | `apps/web/lib/ai.ts` |
| The quiz's schema (the template's) | `apps/web/lib/schemas.ts` |
| The site's name and source link (the rename's seam) | `apps/web/app/site.ts` |
| Workers build and deploy contract | `apps/web/next.config.mjs`, `open-next.config.ts`, `wrangler.jsonc`, `scripts/populate-static-assets-cache.mjs`, `component.yaml`, `tooling/wire/worker-secrets.mjs` |
| Tests | `tests/web` (vitest) |

## Getting started

```bash
pnpm install
pnpm typecheck
pnpm lint
pnpm test
pnpm build            # next build + opennextjs-cloudflare build → apps/web/.open-next
```

That much needs no Cloudflare account and no key: the baseline's own e2e tier
(`testing/e2e.test.sh`) runs exactly this on each landing before a tag, and an
app's developers run it before a push — an app's pull request builds and
dry-deploys it, and does not lint or run the tests. Workers AI has no local
mode, so to make a quiz on your machine either log in to Cloudflare and
preview the built Worker, or give `next dev` a Google key:

```bash
cd apps/web
npx wrangler login                # Workers AI runs on your account, even in wrangler dev
pnpm build && pnpm preview        # wrangler dev over the built Worker
# — or —
cp .env.example .env.local        # GOOGLE_GENERATIVE_AI_API_KEY
pnpm dev                          # http://localhost:3000, quizzes on Gemini
```

| Variable | Where it is read | What it does |
|---|---|---|
| `AI` (binding) | request time, in the Worker (`getCloudflareContext().env`) | Workers AI: the PDF's conversion and, with no Google key, the quiz and its title. Declared in `wrangler.jsonc`; nothing to provision. Absent under `next dev`, where the route answers 503 unless a Google key is set. |
| `GOOGLE_GENERATIVE_AI_API_KEY` | request time, in the Worker (`process.env` under `next dev`) | Optional. A deploy pushes its environment's secret to the Worker, best-effort; the build never has it. Set, the quiz runs on Gemini, which reads the PDF itself. |
| `NEXT_PUBLIC_SITE_URL` | build time (Next.js inlines it into `app/site.ts`) | The site's public origin, for `metadataBase` (the Open Graph image). The deploy sets it per environment: `SITE_URL` when `intent.yaml` sets one, else the Worker's workers.dev URL. |

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting (the pre-rendered page, the route handler, the server action) | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets; the page pre-rendered at build and served from the static-assets cache, which the build fills itself (`scripts/populate-static-assets-cache.mjs`: OpenNext's own `populateCache` would open a Cloudflare session for the AI binding) |
| `@ai-sdk/google` with the project's `GOOGLE_GENERATIVE_AI_API_KEY`: Gemini 1.5 Pro reads the PDF, Gemini 1.5 Flash names the quiz | Workers AI through the Worker's `AI` binding, no key: `env.AI.toMarkdown` converts the PDF, `@cf/zai-org/glm-4.7-flash` writes the quiz and its title through `createAI` (`agents/models/ai-sdk`). With the owner's optional key, Gemini 2.5 Pro and Flash (1.5 is retired), the PDF sent as upstream sent it |
| The key read from the server's environment | An optional Orun secret, unset for the build (`env -u`) and pushed to the Worker as a secret after it (`tooling/wire/worker-secrets.mjs`), read per request |
| `streamObject` with a JSON schema, streamed to `useObject` | The same calls on the AI SDK 7. On Workers AI the streamed call carries the schema in its prompt (Workers AI refuses a schema response format when streaming) and AI SDK's `extractJsonMiddleware` unfences the answer; the stream reaching the page is the same bare array |
| `maxDuration = 60` | Kept; a Worker has no wall-clock limit while its client is connected (its CPU-time limit applies, not the minute) |
| The page's 5 MB limit, checked in the browser | Kept, and also checked by the route (413), with the type (415) and an empty body (400) |
| `@vercel/kv`, `@vercel/analytics`, `@ai-sdk/anthropic`, `@ai-sdk/openai` (dependencies nothing imports) | Not carried |
| `next/font/google` (Geist) | The `geist` package: `next/font/google` fails on GitHub's runners |
| Deploy on push | Orun deploys `<repo>-web-{stage,prod}` on merge to `main` and smoke-tests it (`apps/web/component.yaml`) |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, deployed; the page's button links the product's own "Deploy by hand" |

## CI

| Workflow | What it runs | Ships to an app |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow an app carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the app built and dry-deployed per environment; they do not lint or run the tests), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone is the check; a merge deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
