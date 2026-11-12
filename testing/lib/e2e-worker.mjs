// THE E2E'S OWN ENTRY, never shipped: the built Worker, with its two AI
// providers answered by deterministic in-process stand-ins.
//
// Workers AI has no local mode and cannot be called offline, and Google's
// Gemini needs a key and the network. So this entry, which
// testing/e2e.test.sh copies next to the staged build's .open-next/ (with the
// `ai` block removed from its copy of wrangler.jsonc), gives the Worker:
//
// - `env.AI`, with the binding's own two methods, answering in Workers AI's
//   shapes: toMarkdown(files) reads the uploaded PDF's text-showing operators
//   (`(…) Tj`) into a ConversionResult — so the quiz is built from what really
//   came out of the uploaded bytes — and run(model, inputs, {
//   returnRawResponse }) answers a raw Response: a JSON chat completion, or
//   for `stream: true` the server-sent-event hybrid Workers AI streams (OpenAI
//   delta chunks, a `{ response: "", usage }` tail, [DONE]). The streamed quiz
//   is fenced (```json), as models often write it, and arrives in small
//   chunks with pauses, so a whole question is out before the stream ends;
// - a global fetch that answers generativelanguage.googleapis.com itself —
//   Gemini's streamGenerateContent (SSE) and generateContent (JSON) — wrapped
//   BEFORE the Worker's modules load (a dynamic import, after the wrap:
//   Next.js captures the fetch it patches when its server starts), so the
//   owner's Google key path is served too, and nothing leaves the machine.
//
// GET /__e2e/calls lists what the stand-ins were asked. What this proves is
// the app's half — the upload, the conversion, the prompt, the provider, the
// streamed parse — not that a real model answers: only a deployment does.
const calls = [];

const latin1 = (bytes) => {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return s;
};

function pdfLines(bytes) {
  const lines = [];
  for (const m of latin1(bytes).matchAll(/\(((?:\\.|[^\\)])*)\)\s*Tj/g)) {
    lines.push(m[1].replace(/\\([()\\])/g, "$1"));
  }
  return lines;
}

// Four questions, one per line of the document, the answer rotating A–D.
function quizFrom(lines) {
  const letters = ["A", "B", "C", "D"];
  return [0, 1, 2, 3].map((i) => {
    const options = [`Not stated ${i}a`, `Not stated ${i}b`, `Not stated ${i}c`];
    options.splice(i, 0, lines[i % Math.max(lines.length, 1)] ?? "the document");
    return { question: `Question ${i + 1}: which line does the document contain?`, options, answer: letters[i] };
  });
}

const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const enc = new TextEncoder();
const sse = (o) => enc.encode(`data: ${typeof o === "string" ? o : JSON.stringify(o)}\n\n`);

// A stream of `events`, one every `ms`.
function paced(events, ms) {
  let i = 0;
  return new ReadableStream({
    async pull(controller) {
      if (i >= events.length) return controller.close();
      await pause(ms);
      controller.enqueue(events[i++]);
    },
  });
}

const fakeAI = {
  async toMarkdown(files) {
    const list = Array.isArray(files) ? files : [files];
    const out = [];
    for (const [i, file] of list.entries()) {
      const bytes = new Uint8Array(await file.blob.arrayBuffer());
      calls.push({ kind: "workers-ai.toMarkdown", name: file.name, type: file.blob.type, bytes: bytes.length });
      if (latin1(bytes.slice(0, 5)) !== "%PDF-") {
        out.push({ id: `doc-${i}`, name: file.name, mimeType: file.blob.type, format: "error", error: "Unsupported file" });
        continue;
      }
      const data = `## Contents\n\n${pdfLines(bytes).join("\n\n")}\n`;
      out.push({ id: `doc-${i}`, name: file.name, mimeType: "application/pdf", format: "markdown", tokens: data.split(/\s+/).length, data });
    }
    return Array.isArray(files) ? out : out[0];
  },

  async run(model, inputs, options) {
    const messages = Array.isArray(inputs?.messages) ? inputs.messages : [];
    const text = (role) =>
      messages
        .filter((m) => m.role === role)
        .map((m) => (typeof m.content === "string" ? m.content : JSON.stringify(m.content)))
        .join("\n");
    calls.push({
      kind: "workers-ai.run",
      model,
      stream: Boolean(inputs?.stream),
      responseFormat: inputs?.response_format?.type ?? null,
      raw: Boolean(options?.returnRawResponse),
      system: text("system"),
      user: text("user").slice(0, 8000),
    });
    const usage = { prompt_tokens: 20, completion_tokens: 40, total_tokens: 60 };
    const id = `chatcmpl-${calls.length}`;
    const created = Math.floor(Date.now() / 1000);
    if (!inputs?.stream) {
      // The title, a non-streamed call in JSON mode: words from the file name.
      const name = (text("user").split("\n").pop() || "").trim();
      const title = name.replace(/\.pdf$/i, "").replace(/[-_]+/g, " ").split(/\s+/).slice(0, 3).join(" ") || "quiz";
      const body = {
        id,
        object: "chat.completion",
        created,
        model,
        choices: [{ index: 0, message: { role: "assistant", content: JSON.stringify({ title }) }, finish_reason: "stop" }],
        usage,
      };
      return new Response(JSON.stringify(body), { headers: { "content-type": "application/json" } });
    }
    const doc = /<document[^>]*>\n([\s\S]*?)\n<\/document>/.exec(text("user"))?.[1] ?? "";
    const lines = doc.split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
    const answer = "```json\n" + JSON.stringify({ elements: quizFrom(lines) }) + "\n```";
    const chunk = (delta, finish = null) => ({ id, object: "chat.completion.chunk", created, model, choices: [{ index: 0, delta, finish_reason: finish }], usage });
    const events = (answer.match(/[\s\S]{1,24}/g) ?? []).map((piece) => sse(chunk({ content: piece })));
    events.push(sse(chunk({}, "stop")), sse({ id, object: "chat.completion.chunk", created, model, choices: [], usage }), sse({ response: "", usage }), sse("[DONE]"));
    return new Response(paced(events, 40), { headers: { "content-type": "text/event-stream" } });
  },
};

// Google's Generative Language API, as @ai-sdk/google calls it.
async function gemini(request) {
  const url = new URL(request.url);
  const body = await request.json();
  const parts = (body.contents ?? []).flatMap((c) => c.parts ?? []);
  const pdf = parts.find((p) => p.inlineData?.mimeType === "application/pdf");
  const bytes = pdf ? Uint8Array.from(atob(pdf.inlineData.data), (c) => c.charCodeAt(0)) : new Uint8Array();
  const [, model, method] = /\/models\/([^/:]+):(\w+)$/.exec(url.pathname) ?? [];
  calls.push({
    kind: "gemini",
    model,
    method,
    key: request.headers.get("x-goog-api-key") ?? url.searchParams.get("key"),
    pdfBytes: bytes.length,
    json: body.generationConfig?.responseMimeType === "application/json",
    system: (body.systemInstruction?.parts ?? []).map((p) => p.text).join("\n"),
  });
  const usageMetadata = { promptTokenCount: 20, candidatesTokenCount: 40, totalTokenCount: 60 };
  const candidate = (text, finishReason) => ({ content: { parts: [{ text }], role: "model" }, index: 0, ...(finishReason ? { finishReason } : {}) });
  if (method === "generateContent") {
    const name = parts.map((p) => p.text ?? "").join("\n").trim().split("\n").pop()?.trim() ?? "";
    const title = name.replace(/\.pdf$/i, "").replace(/[-_]+/g, " ").split(/\s+/).slice(0, 3).join(" ") || "quiz";
    return Response.json({ candidates: [candidate(JSON.stringify({ title }), "STOP")], usageMetadata });
  }
  if (method === "streamGenerateContent") {
    const json = JSON.stringify({ elements: quizFrom(pdfLines(bytes)) });
    const pieces = json.match(/[\s\S]{1,80}/g) ?? [];
    const events = pieces.map((p, i) => sse({ candidates: [candidate(p, i === pieces.length - 1 ? "STOP" : undefined)], ...(i === pieces.length - 1 ? { usageMetadata } : {}) }));
    return new Response(paced(events, 40), { headers: { "content-type": "text/event-stream" } });
  }
  return Response.json({ error: { code: 404, message: `no stand-in for ${url.pathname}` } }, { status: 404 });
}

const realFetch = globalThis.fetch;
globalThis.fetch = (input, init) => {
  const request = new Request(input, init);
  if (new URL(request.url).hostname === "generativelanguage.googleapis.com") return gemini(request);
  return realFetch(input, init);
};

const { default: worker } = await import("./.open-next/worker.js");
export default {
  fetch(request, env, ctx) {
    if (new URL(request.url).pathname === "/__e2e/calls") return Response.json(calls);
    return worker.fetch(request, { ...env, AI: fakeAI }, ctx);
  },
};
