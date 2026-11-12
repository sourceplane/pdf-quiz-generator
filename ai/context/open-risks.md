# pdf-quiz-generator — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted ones, is
`specs/epics/pdf-quiz-generator/risks-and-open-questions.md`; this page lists only
what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| PQ-A | Not proven live: repository creation, the brokered token, a real deploy bound to Workers AI, the secret push and the probes | OPEN | One bootstrap from a tag against a workspace |
| PQ-B | No real model has answered: the quiz and the title are proven against in-process stand-ins in Workers AI's and Gemini's shapes. Whether GLM-4.7-Flash follows the schema-in-prompt instruction (and JSON mode for the title) is unproven | OPEN | A quiz from a real PDF on a deployment, on Workers AI and once with a Google key |
| PQ-C | Workers Free's 10 ms CPU a request may not cover decoding a PDF of several megabytes (the JSON body's parse and the base64 decode) | WATCH | A multi-megabyte PDF quizzed on Workers Free; else the README's "Limits" recommends Paid |

Accepted, and worth knowing before you change them: PQ-D (setting a secret
redeploys nothing), PQ-E (the page has no sign-in: quizzes are billed to the
account or the key), PQ-F (`streamObject` is deprecated in the AI SDK 7 and
`createAI` is new: the AI packages move together), PQ-H (only the first
200,000 characters of a document reach Workers AI).
