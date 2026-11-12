# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`pdf-quiz-generator/`](./pdf-quiz-generator/) | **PQ** | In progress (PQ0) | Vercel's PDF to Quiz Generator on Cloudflare Workers + Static Assets through OpenNext, its quiz streamed from Workers AI through the Worker's own binding with no key (Gemini with the owner's optional key), and an Orun baseline that instantiates it in one landing (PQ2) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
