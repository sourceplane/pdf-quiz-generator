# pdf-quiz-generator — implementation plan

Three milestones, each one pull request into `main`, squash-merged once its
CI is green.

## PQ0 — the spec (PQ-1)

The repository is born with its intent, CI, tooling and spec index, and this
doc set (epic.yaml, README, design, this plan, risks, status) and the three
task contracts land.

Done when the doc set and contracts are on `main`.

## PQ1 — the quiz on Workers (PQ-2)

- `apps/web`: the upstream template, its page and components unchanged but
  for the site seam (`app/site.ts`: the name and the source link) and the
  Workers AI wording; Next 15.5.29 and OpenNext 1.20.16; the AI SDK 7,
  `@ai-sdk/react`, zod 4.
- `lib/ai.ts`: the model choice (Workers AI through `createAI`, or Gemini with
  a key) and the schema-in-prompt middleware; `lib/pdf.ts`: the upload
  decoded and checked, the PDF converted.
- The route and the title action on them; the static-assets cache copied by
  the build; `wrangler.jsonc` binding `AI`.
- The Google key as an optional secret pushed by `tooling/wire/worker-secrets.mjs`.
- `tests/web`: the route against a fake binding, the page in jsdom, the model
  choice, the middleware, the PDF decoding, the schema, the site.
- The README and its "How it maps to Vercel" table.

Done when `pnpm typecheck`, `pnpm lint`, `pnpm test` and `pnpm build` are
green and `wrangler dev` makes a quiz from a real PDF on a Workers AI
stand-in (and on a Gemini stand-in with a key).

## PQ2 — a baseline (PQ-3)

- `blueprint.yaml` (the card), `repo-blueprint.yaml` (two phases, one
  landing), `.baseline/` (identity, task contracts, the product README).
- `tooling/rebrand` (the identity), `hooks/render-deployment-docs.sh` (the
  record, the standard library only), `ai/context`, `docs/phases`,
  `BOOTSTRAP.md`.
- `testing/`: manifest, phases, coverage, rebrand, retouch, bootstrap-defer,
  render, leak, placement and the e2e with its in-process stand-ins; the
  component docs generated.

Done when every Baseline CI tier is green, then `baseline-v1` is cut.
