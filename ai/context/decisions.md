# pdf-quiz-generator — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | OpenNext on Workers + Static Assets (`cloudflare-workers-assets-turbo`), the static-assets incremental cache; no R2 or Durable Object cache | Nothing is revalidated: the page is pre-rendered once, the route streams per request | `specs/epics/pdf-quiz-generator/design.md` §2 |
| 2 | The build fills the static-assets cache itself (`apps/web/scripts/populate-static-assets-cache.mjs`), not with `opennextjs-cloudflare populateCache local` | That command opens wrangler's platform proxy over `wrangler.jsonc`, and the AI binding (no local simulator) makes it ask for a Cloudflare credential; a build needs none (ai-chatbot's pattern) | design.md §2 |
| 3 | Workers AI through the Worker's `AI` binding is the default: `env.AI.toMarkdown` converts the PDF, `@cf/zai-org/glm-4.7-flash` writes the quiz and its title | Gemini 1.5 is retired, and a key-free default lets a bootstrap make quizzes from its first deploy | design.md §3 |
| 4 | `createAI` from `agents/models/ai-sdk`, which needs the AI SDK 7 (from the template's 4), `@ai-sdk/react` for `experimental_useObject`, `instructions` for the system prompt, zod 4 | `workers-ai-provider` is deprecated and feature-frozen (Cloudflare, 2026-10-21); `createAI` replaces it | design.md §3, risk PQ-F |
| 5 | A streamed structured call to Workers AI carries its JSON schema in the system prompt, with no response format, and AI SDK's `extractJsonMiddleware` unfences the answer; the non-streamed title keeps JSON mode | Workers AI refuses a JSON-schema response format on a streamed request | design.md §3, risk PQ-B |
| 6 | `streamObject` kept (deprecated in the AI SDK 7, still functional) | Its text stream is the bare array the template's `useObject` parses: the page's contract is unchanged | risk PQ-F |
| 7 | `GOOGLE_GENERATIVE_AI_API_KEY` is `optionalSecretEnv`, unset for the build (`env -u`) and pushed to the Worker as a secret after it; with it, Gemini (`gemini-2.5-pro`, `gemini-2.5-flash`) reads the PDF itself | A required ref fails the lane before its first step on a fresh product; a key read per request never sits in a bundle (algolia-search's pattern) | design.md §3 |
| 8 | The route checks the upload (400 no file, 415 not a PDF, 413 over 5 MB, 422 no text) before any model is asked | The page checked only in the browser; a refusal must not spend | design.md §4 |
| 9 | Next 15.5.29 (the template's 15.5 line) with @opennextjs/cloudflare 1.20.16, both pinned | 1.20.16's peer range is `>=15.5.29 <16 || >=16.4.5` | risk PQ-G |
| 10 | Two phases, one landing (`01-product`, `02-docs`), no infra component | A landing has a fixed cost (cirrus-baseline since baseline-v22); the app provisions nothing | design.md §5 |
| 11 | `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME`; stack-tectonic 0.19.0, not 0.20.0 | A bootstrap cannot set a repository variable; a Next 16 move would meet Turbopack's refusal of 0.20.0's out-of-tree `node_modules` | risk PQ-I |
| 12 | The e2e serves the built Worker through its own entry with in-process stand-ins for Workers AI and Gemini | Workers AI has no local mode and Gemini needs a key; a test seam does not belong in the product | design.md §6 |
| 13 | Component docs are generated from the manifests and checked in CI | A hand-written copy of the dependency graph and bindings drifts silently | `tooling/catalog/gen-component-docs.py` |
| 14 | The workers.dev subdomain is read from the Cloudflare connection; the console asks for no domain, and an empty `productdomain` brands the placeholder `<reponame>.example.com` | One right answer for the subdomain; a domain is an owner's step after the bootstrap | `blueprint.yaml`, `tooling/rebrand/rebrand.mjs` |
| 15 | The deployment-record hook uses the Python standard library only, tested without PyYAML | The console's build box has python3 but not PyYAML (orun-cloud#2344) | `testing/render.test.sh` |
