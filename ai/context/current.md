# pdf-quiz-generator — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to an app built from it; the
two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Vercel's PDF to Quiz Generator (the AI SDK's PDF example) on Cloudflare
Workers + Static Assets (`@opennextjs/cloudflare`) — a PDF uploaded, turned
into Markdown by Workers AI, and a four-question quiz streamed back from
`@cf/zai-org/glm-4.7-flash` through the Worker's own binding, with no key —
packaged as an Orun baseline: `orun new --blueprint repo-blueprint.yaml`
builds a new app in its own repository and takes it to live on stage and
prod in one landing (`01-product`), then records what went live (`02-docs`).
With the owner's optional Google key, Gemini makes the quizzes instead, from
the PDF itself, as upstream did. There is no infra component: Workers AI is a
binding with nothing to provision.

## Release

| | |
|---|---|
| Latest tag | `baseline-v1` (PQ2 — the baseline, one landing) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI, on in-process stand-ins for Workers AI and Gemini; a live bootstrap (risk PQ-A) and a real model's answer (risk PQ-B) are still to come |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/pdf-quiz-generator/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/pdf-quiz-generator/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/pdf-quiz-generator/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `apps/web/docs/`, `tests/web/docs/` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one app from `baseline-v1` against a workspace, and record its
   timings (closes PQ-A).
2. Make a quiz from a real PDF on Workers AI, and once with a Google key
   (closes PQ-B).
