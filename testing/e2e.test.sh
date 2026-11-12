#!/usr/bin/env bash
# TIER 2 — the quiz app a bootstrap produces builds, deploys (dry) and serves,
# first on Workers AI with no key (as every product starts), then with its
# owner's optional Google key.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree.
# This proves it WORKS, by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its one pull request merges), the
#      landing's own checks — install with the lockfile the product ships,
#      render fixtures and check the committed config is the render,
#      typecheck, lint, test, build. The bootstrap's landings are checked in
#      the box with `orun validate` and `orun plan` alone (`checks: local`;
#      their PR's CI on an `orun/BASE-…` branch is `plan` alone), and a
#      product's later pull requests build and dry-deploy it through ci.yml's
#      lanes, so THIS is where a product those steps refuse is caught: before
#      the tag, not after a build has merged it. Then the same at the 02-docs
#      landing, the finished app;
#   2. the stage lane's own steps, read out of `orun plan` in the product for
#      a pull request (the verify profile: the deploy profile has no dry run)
#      — EVERY `run:` step of the job, in order, exactly as planned: the
#      install, `verify-app-structure` (the committed `package.json` and
#      `wrangler.jsonc`, checked BEFORE any build), `build-app` (TypeGen,
#      `next build`, the OpenNext bundle, the static-assets cache copy, then
#      tooling/wire/worker-secrets.mjs), `verify-build-output` and
#      `deploy-dry-run` (`wrangler deploy --dry-run --name
#      <reponame>-web-stage`, which must bind Workers AI as AI). They run IN
#      THE TREE THE RUNNER STAGES for the job (testing/lib/stage-job.py), with
#      no build output in it and the dependency layout the pinned composition
#      produces. The job's Google key ref is optional; here the lane is given
#      it, as an owner who has stored one gives it, so this can prove the
#      build never sees it (`env -u`: the value is nowhere in .next or
#      .open-next) and that a verify lane, which holds no Cloudflare
#      credential, pushes nothing to a Worker;
#   3. serve the built Worker with `wrangler dev`, as a product with no key is
#      served: through the e2e's own entry (testing/lib/e2e-worker.mjs), which
#      answers the Worker's AI binding in-process — Workers AI has no local
#      mode — with nothing else changed. Run the component's OWN
#      `smokeCommand` against it, verbatim and then inside the deploy
#      profile's planned `smoke` step (its retry loop and all — only its
#      workers.dev URL swapped for the local one); then read what the app
#      promises: the page under the product's name and source link, its Open
#      Graph image on the stage origin and its static assets; a real PDF
#      uploaded to /api/generate-quiz, converted by the binding's toMarkdown
#      and its four questions streamed back — the first whole before the
#      stream ends — built from that PDF's own text; the quiz's title from
#      the server action; and the route's refusals (400, 413, 415);
#   4. serve the SAME build with the owner's Google key, as the deploy gives
#      it: the same quiz now comes from Gemini (the entry answers Google's API
#      host in-process), which is sent the PDF itself and the key, while the
#      Workers AI binding is never called.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered Cloudflare token, deploy for real and probe workers.dev — nor ask a
# real model: whether Workers AI or Gemini answers the prompt well is only
# seen live. That is a bootstrap against a workspace (BOOTSTRAP.md);
# everything short of it is here.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, setsid, and the
# network for `pnpm install` (or a warm store). Several minutes: three
# installs and three Next.js builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git curl setsid; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
dev_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So it is
# started as its own process group (setsid) and the whole group is stopped.
stop_group() { # PGID
  [ -n "$1" ] || return 0
  kill -TERM -- "-$1" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$1" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$1" 2>/dev/null || true
}
cleanup() {
  stop_group "$dev_pid"
  rm -rf "$scratch"
}
trap cleanup EXIT
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
sub="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['subdomain'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false NEXT_TELEMETRY_DISABLED=1 TURBO_TELEMETRY_DISABLED=1
# NO Google key and NO Cloudflare credential, whatever the caller's shell
# holds: the lane below is given the key exactly as the e2e sets it, and a
# verify lane never holds a Cloudflare token.
unset GOOGLE_GENERATIVE_AI_API_KEY CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID
free_port() { python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"; }

# The landing's own checks, step for step, run here at once on the whole
# tree. A pull request in the product builds and dry-deploys the app through
# ci.yml's lanes; the lint and the tests run here, and by hand before a push.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "git diff --exit-code"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
s00="$(git -C "$tree" rev-parse HEAD~2)"; s01="$(git -C "$tree" rev-parse HEAD~1)"
echo "   2 phases placed and landed on orun's Initial commit"

# ── 1. each landing's own checks ───────────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
git -C "$tree" worktree add -q "$scratch/at-01" "$s01"
checks "$scratch/at-01" "$scratch/checks-01.log"
# Its tree is not needed again, and the disk is shared.
git -C "$tree" worktree remove --force "$scratch/at-01"

echo "── 02-docs's landing (the finished app): the same checks"
checks "$tree" "$scratch/checks-app.log"
# The template's Next.js line, which the deploy builds with (OpenNext 1.20.16
# takes Next.js 15 from 15.5.29).
grep -q 'Next.js 15\.5\.' "$scratch/checks-app.log" \
  || { echo "FAIL: the landing's build is not on the template's Next.js 15.5" >&2; grep -m3 'Next.js' "$scratch/checks-app.log" >&2; exit 1; }

# ── 2. the stage lane, as a pull request plans it ──────────────────────────
echo "── the stage lane: every run step the PR plan gives web@stage, in a staged job tree"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base "$s00" --head "$s01" --env stage --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan-pr.log" >&2; exit 1; }
python3 - "$scratch/plan-pr.json" "$scratch/steps" "$tree" "$values" <<'PY'
import json, pathlib, sys
import yaml
plan = json.load(open(sys.argv[1]))
out = pathlib.Path(sys.argv[2]); out.mkdir()
tree, values = pathlib.Path(sys.argv[3]), json.load(open(sys.argv[4]))
repo, ws = values["reponame"], values["orunWorkspace"]
job = next(j for j in plan["jobs"] if j["component"] == "web" and j["environment"] == "stage")
params = yaml.safe_load((tree / "apps/web/component.yaml").read_text())["spec"]["parameters"]
order, uses = [], []
for s in job["steps"]:
    if "use" in s:
        uses.append(f"{s['id']}\t{s['use']}\t{json.dumps(s.get('with') or {})}")
        continue
    order.append(s["id"])
    (out / f"{s['id']}.sh").write_text(s.get("run") or "")
    (out / f"{s['id']}.wd").write_text(s.get("working-directory") or ".")
    if s.get("scope"):
        (out / f"{s['id']}.scope").write_text(s["scope"])
(out / "order").write_text("\n".join(order) + "\n")
(out / "uses").write_text("\n".join(uses) + "\n")
(out / "path").write_text(job.get("path") or "apps/web")
(out / "profile").write_text(job["profile"])
(out / "node").write_text(params["nodeVersion"])
(out / "pnpm").write_text(params["pnpmVersion"])
for k, v in (job.get("env") or {}).items():
    (out / "env").open("a").write(f"export {k}={json.dumps(v)}\n")
# What the platform resolves into the job before its first step. The Google
# key's ref is OPTIONAL: on a product whose owner stored none, nothing is
# exported; on one that has, it is — which is what this lane replays.
refs = {r["asEnv"]: r for r in job.get("secretRefs") or []}
r = refs.get("GOOGLE_GENERATIVE_AI_API_KEY")
if not r or r.get("optional") is not True or f"/{repo}/stage/" not in r.get("ref", ""):
    sys.exit(f"FAIL: the stage lane resolves GOOGLE_GENERATIVE_AI_API_KEY as {r} — want an optional ref to the product's stage secret")
required = sorted(k for k, r in refs.items() if not r.get("optional"))
if required:
    sys.exit(f"FAIL: the verify lane requires secrets {required}; a pull request's lane needs none")
PY
order="$(tr '\n' ' ' < "$scratch/steps/order")"
echo "   $(cat "$scratch/steps/profile"): $order"
for need in install-workspace-dependencies verify-app-structure build-app verify-build-output deploy-dry-run; do
  grep -qx "$need" "$scratch/steps/order" || { echo "FAIL: the stage lane plans no $need step" >&2; exit 1; }
done
[ "$(grep -n -x verify-app-structure "$scratch/steps/order" | cut -d: -f1)" -lt "$(grep -n -x build-app "$scratch/steps/order" | cut -d: -f1)" ] \
  || { echo "FAIL: the structure check is planned after the build" >&2; exit 1; }
# The `use:` steps set up the runner's toolchain; here it is this machine's,
# so it must be the one the component asks for.
node_major="$(node -p 'process.versions.node.split(".")[0]')"
[ "$node_major" = "$(cat "$scratch/steps/node")" ] || { echo "FAIL: node $node_major here, the lane sets up $(cat "$scratch/steps/node")" >&2; exit 1; }
[ "$(pnpm --version)" = "$(cat "$scratch/steps/pnpm")" ] || { echo "FAIL: pnpm $(pnpm --version) here, the lane sets up $(cat "$scratch/steps/pnpm")" >&2; exit 1; }
echo "   setup-node $node_major and setup-pnpm $(pnpm --version) stand in for the lane's \`use:\` steps"
echo "   the Google key's ref is optional: the lane runs with it set, as an owner's who stored one does"

# The job's private tree, staged as orun stages it, from a source checkout
# with no build output (a CI checkout has none, so step 1's is removed rather
# than copied in) and the dependencies the pinned composition says: a
# lane-scoped install ran once in the source tree (step 1 ran the same
# command) and is linked in, or the job installs its own.
rm -rf "$tree/apps/web/.next" "$tree/apps/web/.open-next" "$tree/apps/web/.wrangler" "$tree/tests/web/coverage"
work="$tree/.orun/runs/e2e/web.stage.verify-deploy/work"
install_scope="$(cat "$scratch/steps/install-workspace-dependencies.scope" 2>/dev/null || echo job)"
if [ "$install_scope" = lane ]; then
  python3 "$here/lib/stage-job.py" "$tree" "$work" --shared-deps
  [ -L "$work/node_modules" ] || { echo "FAIL: the staged tree's node_modules is not the lane's symlink" >&2; exit 1; }
else
  python3 "$here/lib/stage-job.py" "$tree" "$work"
  [ ! -e "$work/node_modules" ] || { echo "FAIL: the staged tree carries node_modules it should install" >&2; exit 1; }
fi
for built in apps/web/.next apps/web/.open-next apps/web/.wrangler; do
  [ ! -e "$work/$built" ] || { echo "FAIL: the staged tree carries build output ($built)" >&2; exit 1; }
done
echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: $install_scope; no build output"

# The key the platform would resolve for an owner who stored one: a value no
# file in the tree spells, so a match in the build output can only be a leak.
build_key="e2e-build-key-$(python3 -c 'import secrets;print(secrets.token_hex(12))')"
export GOOGLE_GENERATIVE_AI_API_KEY="$build_key"
while IFS= read -r step; do
  [ -n "$step" ] || continue
  if [ "$step" = install-workspace-dependencies ] && [ "$install_scope" = lane ]; then
    echo "   · $step (lane-scoped: ran once in the source tree)"; continue
  fi
  echo "   ▸ $step"
  # The runner's per-job environment: the job's env (intent environment
  # `env:`) and ORUN_ENVIRONMENT; the step runs in the component's directory.
  if ! (cd "$work/$(cat "$scratch/steps/path")/$(cat "$scratch/steps/$step.wd")" && \
        { [ -f "$scratch/steps/env" ] && source "$scratch/steps/env"; true; } && \
        export ORUN_ENVIRONMENT=stage && bash -e "$scratch/steps/$step.sh") > "$scratch/$step.log" 2>&1; then
    echo "FAIL: the stage lane's $step step" >&2; tail -40 "$scratch/$step.log" >&2; exit 1
  fi
done < "$scratch/steps/order"
unset GOOGLE_GENERATIVE_AI_API_KEY
[ "$install_scope" = lane ] || { [ -d "$work/node_modules" ] && [ ! -L "$work/node_modules" ]; } \
  || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
grep -q 'Next.js 15\.5\.' "$scratch/build-app.log" \
  || { echo "FAIL: the staged build is not on the template's Next.js 15.5" >&2; grep -m3 'Next.js' "$scratch/build-app.log" >&2; exit 1; }
grep -q 'populate: the static-assets incremental cache' "$scratch/build-app.log" \
  || { echo "FAIL: the build did not copy the pre-rendered pages into the static assets" >&2; exit 1; }
grep -q -- "--name \"\${EFFECTIVE_WORKER_NAME}\"" "$scratch/steps/deploy-dry-run.sh" && grep -q "$repo-web-stage" "$scratch/steps/deploy-dry-run.sh" \
  || { echo "FAIL: the dry run does not name the Worker $repo-web-stage" >&2; exit 1; }
grep -q 'Total Upload' "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run bundled nothing" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
grep -Eq 'env\.AI +AI' "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind Workers AI as AI" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
gz="$(grep -m1 -o 'gzip: [0-9.]* KiB' "$scratch/deploy-dry-run.log" | grep -o '[0-9.]*')"
python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) <= 3072 else 1)" "${gz:-99999}" \
  || { echo "FAIL: the Worker is ${gz:-of unknown size} KiB gzipped — over Workers Free's 3 MiB" >&2; exit 1; }
echo "   the staged build ran on Next.js 15.5; the dry run bundled $repo-web-stage with Workers AI as AI ($(grep -m1 -o 'Total Upload: .*' "$scratch/deploy-dry-run.log"))"
if grep -rlF -e "$build_key" "$work/apps/web/.open-next" "$work/apps/web/.next" > "$scratch/leaked.txt" 2>/dev/null; then
  echo "FAIL: the Google key is in the build output:" >&2; head -5 "$scratch/leaked.txt" >&2; exit 1
fi
grep -q "worker-secrets: no Cloudflare credential in this job (a verify lane) — GOOGLE_GENERATIVE_AI_API_KEY reach $repo-web-stage from the deploy lane" "$scratch/build-app.log" \
  || { echo "FAIL: build-app did not hand the Google key to worker-secrets.mjs (or pushed it from a verify lane)" >&2; grep -m3 'worker-secrets' "$scratch/build-app.log" >&2; exit 1; }
echo "   the build never saw the key; worker-secrets.mjs named it and pushed nothing from a verify lane"

# ── 3. serve it, and smoke it as the deploy does ───────────────────────────
# The Worker's config with ONE change, its `main`: the e2e's own entry, which
# imports the built Worker and hands it an in-process Workers AI. The `ai`
# block goes: Workers AI has no local mode, and wrangler would open a session
# to a Cloudflare account for it.
cp "$here/lib/e2e-worker.mjs" "$work/apps/web/e2e-worker.mjs"
python3 - "$work/apps/web/wrangler.jsonc" "$work/apps/web/wrangler.e2e.jsonc" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
text, n_main = re.subn(r'"main":\s*"\.open-next/worker\.js"', '"main": "e2e-worker.mjs"', text)
text, n_ai = re.subn(r'\n\s*"ai":\s*\{\s*"binding":\s*"AI"\s*\},?', "", text)
if (n_main, n_ai) != (1, 1):
    sys.exit(f"FAIL: wrangler.jsonc has {n_main} main and {n_ai} ai block(s), want one of each")
open(sys.argv[2], "w").write(text)
PY
action="$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
ids=[k for k,v in d['node'].items() if 'actions' in json.dumps(v)]
assert len(ids)==1, ids
print(ids[0])" "$work/apps/web/.next/server/server-reference-manifest.json")"
serve() { # LOG [--var K:V …]
  local log="$1"; shift
  port="$(free_port)"; iport="$(free_port)"
  # setsid without its own fork: the subshell is not a group leader, so the
  # pid recorded IS the new process group's.
  (cd "$work/apps/web" && exec setsid pnpm exec wrangler dev --config wrangler.e2e.jsonc --name "$repo-web-stage" "$@" \
     --ip 127.0.0.1 --port "$port" --inspector-port "$iport" --show-interactive-dev-session=false) \
     > "$log" 2>&1 < /dev/null &
  dev_pid=$!
  url="http://127.0.0.1:$port"
  for _ in $(seq 1 120); do
    curl -s -o /dev/null "$url/favicon.ico" && return 0
    kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$log" >&2; exit 1; }
    sleep 1
  done
  echo "FAIL: wrangler dev never answered" >&2; tail -30 "$log" >&2; exit 1
}

echo "── wrangler dev over the staged Worker, no Google key: Workers AI"
serve "$scratch/dev.log"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
echo "   ▸ the component's own smokeCommand, verbatim, DEPLOYED_URL=$url"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the app" >&2; exit 1; }
if DEPLOYED_URL="$url/no-such-app" bash -c "$smoke" 2>/dev/null; then
  echo "FAIL: the smoke passed against a path that is not the app — it checks nothing" >&2; exit 1
fi
echo "   ▸ …and it refuses what is not the app"

(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --changed \
   --base "$s00" --head "$s01" --env stage --output "$scratch/plan-push.json") > "$scratch/plan-push.log" 2>&1 \
  || { echo "FAIL: orun plan (push to main)" >&2; tail -15 "$scratch/plan-push.log" >&2; exit 1; }
python3 - "$scratch/plan-push.json" "$scratch/smoke-step.sh" "https://$repo-web-stage.$sub.workers.dev" <<'PY'
import json, sys
plan, out, origin = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
job = next(j for j in plan["jobs"] if j["component"] == "web" and j["environment"] == "stage")
assert job["profile"].endswith(".deploy"), job["profile"]
run = next(s for s in job["steps"] if s["id"] == "smoke")["run"]
# The one thing offline cannot reach is workers.dev: the step derives its URL
# from the Worker's name and the account's subdomain, so that line — and only
# that line — is pointed at the local Worker, after checking it is this app's.
line = 'export DEPLOYED_URL="https://${EFFECTIVE_WORKER_NAME}.${WORKERS_DEV_SUBDOMAIN}.workers.dev"'
if line not in run or 'EFFECTIVE_WORKER_NAME="' + origin.split("//")[1].split(".")[0] + '"' not in run:
    sys.exit(f"FAIL: the planned smoke step does not derive {origin}:\n{run}")
open(out, "w").write(run.replace(line, 'export DEPLOYED_URL="${E2E_LOCAL_URL}"'))
PY
echo "   ▸ the deploy profile's planned smoke step (its retry loop around the same command), on the local Worker"
(E2E_LOCAL_URL="$url" bash "$scratch/smoke-step.sh") > "$scratch/smoke-step.log" 2>&1 \
  || { echo "FAIL: the planned smoke step refused the app" >&2; tail -20 "$scratch/smoke-step.log" >&2; exit 1; }

# The quiz checks, shared by both serves: PROVIDER is workers-ai or gemini.
cat > "$scratch/quiz.py" <<'PY'
import base64, html, http.client, json, re, sys, time, urllib.error, urllib.request
base, values, origin, action, provider = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3], sys.argv[4], sys.argv[5]
name, repo, owner = values["productname"], values["reponame"], values["githuborg"]
problems = []
def bad(m): problems.append(m)
def get(path):
    try:
        with urllib.request.urlopen(base + path, timeout=60) as r:
            return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()
def post(path, body, headers):
    req = urllib.request.Request(base + path, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()

# A one-page PDF with known text, standard library only: one `(…) Tj` a line.
LINES = ["The Zephyr pelican crosses Lake Orvel every April.",
         "Its wings span three metres and carry it far each day.",
         "Marsh reeds at Orvel feed the flock on the way north.",
         "Rangers count the pelicans from the Kestrel tower."]
def make_pdf(lines):
    esc = lambda s: s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    content = "\n".join(["BT", "/F1 12 Tf", "72 720 Td", "16 TL"] + [x for l in lines for x in (f"({esc(l)}) Tj", "T*")] + ["ET"]).encode("latin-1")
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream"]
    out, offs = bytearray(b"%PDF-1.4\n"), []
    for n, body in enumerate(objs, 1):
        offs.append(len(out)); out += f"{n} 0 obj\n".encode() + body + b"\nendobj\n"
    x = len(out); out += f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n".encode()
    for o in offs: out += f"{o:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{x}\n%%EOF\n".encode()
    return bytes(out)
pdf = make_pdf(LINES)
def upload(data, fname="zephyr-pelicans.pdf", ctype="application/pdf"):
    return json.dumps({"files": [{"name": fname, "type": ctype, "data": f"data:{ctype};base64," + base64.b64encode(data).decode()}]}).encode()

# The page: the product's name and source, no Vercel, its card and assets.
if provider == "workers-ai":
    s, h, body = get("/")
    page = body.decode().replace("<!-- -->", "")
    title = re.search(r"<title>(.*?)</title>", page, re.S)
    if s != 200 or not title or html.unescape(title.group(1)) != name:
        bad(f"/ answered {s} titled {title and html.unescape(title.group(1))!r}, not {name!r}")
    text = html.unescape(re.sub(r"<[^>]+>", " ", page))
    if name not in text or "Drop your PDF here or click to browse." not in text:
        bad("the page does not show the product's name, or the upload card")
    src = f"https://github.com/{owner}/{repo}"
    if f'href="{src}"' not in page or f'href="{src}#deploy-by-hand"' not in page:
        bad(f"the page does not link the product's own source {src} (and its Deploy by hand)")
    if "Deploy with Vercel" in text or "ai-sdk-preview-pdf-support" in page or "PDF Support Preview" in text:
        bad("the page still carries the template's Vercel links or name")
    og = re.search(r'<meta property="og:image" content="([^"]+)"', page)
    if not og or not og.group(1).startswith(origin + "/opengraph-image"):
        bad(f"the Open Graph image is {og and og.group(1)!r}, not on the stage origin {origin}")
    else:
        s, h, _ = get(og.group(1)[len(origin):])
        if s != 200 or not (h.get("content-type") or "").startswith("image/png"):
            bad(f"the Open Graph image answered {s} {h.get('content-type')}")
    chunk = re.search(r'src="(/_next/static/[^"]+\.js)"', page)
    s, h, _ = get(chunk.group(1)) if chunk else (0, {}, b"")
    if not chunk or s != 200 or "javascript" not in (h.get("content-type") or ""):
        bad("the page's /_next/static script did not load")
    s, h, _ = get("/favicon.ico")
    if s != 200:
        bad(f"/favicon.ico answered {s}")
    s, _, _ = get("/no-such-page")
    if s != 404:
        bad(f"/no-such-page answered {s}, want 404")

# The quiz: a real PDF up, four questions streamed back, timed.
host, port = base.split("//")[1].split(":")
c = http.client.HTTPConnection(host, int(port), timeout=60)
t0 = time.time()
c.request("POST", "/api/generate-quiz", upload(pdf), {"content-type": "application/json"})
r = c.getresponse()
chunks = []
while True:
    b = r.read1(65536)
    if not b: break
    chunks.append((time.time() - t0, b.decode()))
streamed = "".join(t for _, t in chunks)
if r.status != 200 or not (r.getheader("content-type") or "").startswith("text/plain"):
    bad(f"/api/generate-quiz answered {r.status} {r.getheader('content-type')}")
sofar, first = "", None
for i, (_, t) in enumerate(chunks):
    sofar += t
    if first is None and '"answer"' in sofar:
        first = i
if first is None or first >= len(chunks) - 1:
    bad(f"no whole question arrived before the stream ended ({len(chunks)} chunks)")
try:
    quiz = json.loads(streamed)
except ValueError:
    quiz = None
    bad(f"the quiz stream is not JSON: {streamed[:120]!r}")
if quiz is not None:
    ok = isinstance(quiz, list) and len(quiz) == 4 and all(
        isinstance(q.get("question"), str) and len(q.get("options", [])) == 4 and q.get("answer") in ("A", "B", "C", "D") for q in quiz)
    if not ok:
        bad(f"the quiz is not four questions of four options: {streamed[:200]!r}")
    elif [q["options"]["ABCD".index(q["answer"])] for q in quiz] != LINES:
        bad("the quiz's answers are not the uploaded PDF's own lines")

# The title, from the page's server action.
s, _, body = post("/", json.dumps(["zephyr-pelicans.pdf"]).encode(),
                  {"Next-Action": action, "Content-Type": "text/plain;charset=UTF-8", "Accept": "text/x-component"})
if s != 200 or '"zephyr pelicans"' not in body.decode():
    bad(f"the title action answered {s}: {body.decode()[-120:]!r}")

calls = json.loads(get("/__e2e/calls")[2])
if provider == "workers-ai":
    conv = [x for x in calls if x["kind"] == "workers-ai.toMarkdown"]
    runs = [x for x in calls if x["kind"] == "workers-ai.run"]
    if [x["bytes"] for x in conv] != [len(pdf)]:
        bad(f"Workers AI's conversion was given {[x['bytes'] for x in conv]} bytes, not the {len(pdf)} uploaded")
    quiz_run = [x for x in runs if x["stream"]]
    title_run = [x for x in runs if not x["stream"]]
    if len(quiz_run) != 1 or quiz_run[0]["model"] != "@cf/zai-org/glm-4.7-flash" or quiz_run[0]["responseFormat"] is not None:
        bad(f"the quiz did not stream from @cf/zai-org/glm-4.7-flash without a response format: {quiz_run}")
    elif not quiz_run[0]["system"].startswith("You are a teacher.") or "Answer with JSON only" not in quiz_run[0]["system"] \
            or not all(l in quiz_run[0]["user"] for l in LINES):
        bad("the quiz's prompt is not the teacher's, the schema and the PDF's text")
    if len(title_run) != 1 or title_run[0]["responseFormat"] != "json_schema":
        bad(f"the title was not one JSON-mode call: {title_run}")
    if any(x["kind"] == "gemini" for x in calls):
        bad("Gemini was called with no Google key stored")
else:
    gem = [x for x in calls if x["kind"] == "gemini"]
    want = [("gemini-2.5-pro", "streamGenerateContent"), ("gemini-2.5-flash", "generateContent")]
    if sorted((x["model"], x["method"]) for x in gem) != sorted(want):
        bad(f"Gemini was asked {[(x['model'], x['method']) for x in gem]}, not {want}")
    if any(x["key"] != sys.argv[6] for x in gem):
        bad("a Gemini request did not carry the owner's key")
    q = [x for x in gem if x["method"] == "streamGenerateContent"]
    if not q or q[0]["pdfBytes"] != len(pdf) or not q[0]["json"] or not q[0]["system"].startswith("You are a teacher."):
        bad(f"Gemini was not sent the PDF itself under the teacher's prompt, in JSON mode: {q}")
    if any(x["kind"].startswith("workers-ai") for x in calls):
        bad("Workers AI was called although the owner's Google key is stored")

# The route's refusals: nothing reaches a model.
before = len(calls)
for desc, body, want in (("no file", b"{}", 400),
                         ("a text file", upload(b"hello", "a.txt", "text/plain"), 415),
                         ("bytes that are not a PDF", upload(b"hello"), 415),
                         ("a PDF over 5 MB", upload(b"%PDF-1.4\n" + b"0" * (5 * 1024 * 1024)), 413)):
    s, _, _ = post("/api/generate-quiz", body, {"content-type": "application/json"})
    if s != want:
        bad(f"{desc} answered {s}, want {want}")
if len(json.loads(get("/__e2e/calls")[2])) != before:
    bad("a refused upload still reached a model")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
first_at = chunks[first][0] if first is not None else 0
print(f"   {provider}: four questions from the PDF's own lines in {len(chunks)} chunks, the first whole at "
      f"{first_at:.2f}s of {chunks[-1][0]:.2f}s; the title; the refusals (400, 413, 415)")
PY

echo "   ▸ the page, its assets, and a quiz from a real PDF, on Workers AI"
python3 "$scratch/quiz.py" "$url" "$values" "https://$repo-web-stage.$sub.workers.dev" "$action" workers-ai \
  || { echo "FAIL: the app on Workers AI" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }

# ── 4. the same build, with the owner's Google key ─────────────────────────
echo "── the same build, with the owner's Google key: Gemini"
stop_group "$dev_pid"; dev_pid=""
key="e2e-google-key-$(python3 -c 'import secrets;print(secrets.token_hex(8))')"
serve "$scratch/dev-gemini.log" --var "GOOGLE_GENERATIVE_AI_API_KEY:$key"
echo "   ▸ the component's own smokeCommand, with the key"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the app with a Google key" >&2; exit 1; }
echo "   ▸ the same quiz, from Gemini"
python3 "$scratch/quiz.py" "$url" "$values" "https://$repo-web-stage.$sub.workers.dev" "$action" gemini "$key" \
  || { echo "FAIL: the app with a Google key" >&2; tail -20 "$scratch/dev-gemini.log" >&2; exit 1; }

echo "e2e.test.sh: ok"
