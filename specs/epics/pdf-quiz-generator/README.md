# pdf-quiz-generator — Vercel's PDF to Quiz Generator on Cloudflare Workers

**The AI SDK's PDF example — a PDF in, a four-question quiz streamed back —
served by one Cloudflare Worker, its quiz written by Workers AI through the
Worker's own binding with no key, deployed by Orun to stage and prod on every
merge, and the baseline that makes a copy of it somebody else's in one
landing.**

| | |
|---|---|
| Status | In progress — PQ1 on main: the site runs on Workers |
| Upstream | [vercel-labs/ai-sdk-preview-pdf-support](https://github.com/vercel-labs/ai-sdk-preview-pdf-support) (Apache-2.0, © 2024 Vercel), at `2216bb6` (2026-04-25) — Vercel's "PDF to Quiz Generator" template |
| Reference | [microcms-blog](https://github.com/sourceplane/microcms-blog) — the same scaffolding, tests, bootstrap, an optional key pushed to the Worker after the build, and the e2e's own Worker entry; [nuxt-ai-editor](https://github.com/sourceplane/nuxt-ai-editor) — Workers AI through the binding with an optional key |
| Key | `PQ` |

Vercel's [PDF to Quiz Generator](https://github.com/vercel-labs/ai-sdk-preview-pdf-support)
(vercel-labs/ai-sdk-preview-pdf-support, Apache-2.0) is the AI SDK's PDF
example: upload a PDF and get a four-question multiple-choice quiz about it,
streamed with `streamObject` into `useObject`, then the quiz, its score and
its review. This epic runs it on Cloudflare Workers + Static Assets through
`@opennextjs/cloudflare`, its quiz written by Workers AI through the Worker's
own binding — no key — and packages it as an Orun baseline that takes a new
quiz app from nothing to live on stage and prod in one landing.

The template's Gemini 1.5 models are retired; with the owner's optional
Google key the app runs on their successors, which read the PDF itself as
upstream did.

## Read in this order

| Page | What it answers |
|---|---|
| [design.md](design.md) | how the template maps to Workers, the model and provider choice, the streaming constraint, the repository and the build |
| [implementation-plan.md](implementation-plan.md) | the three milestones and what each one ships |
| [risks-and-open-questions.md](risks-and-open-questions.md) | what is not yet proven, and what is accepted |
| [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) | what shipped, and every departure from upstream |

## Milestones

| Milestone | What it lands | Task |
|---|---|---|
| PQ0 — the spec | the repository, its intent, CI, tooling and spec index; this doc set | PQ-1 |
| PQ1 — the quiz on Workers | the template in `apps/web`, built by OpenNext into one Worker bound to Workers AI, the Google key read per request; `tests/web` | PQ-2 |
| PQ2 — a baseline | the console card, the build document, the context pack and the baseline's tests | PQ-3 |
