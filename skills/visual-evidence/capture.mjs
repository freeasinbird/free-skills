#!/usr/bin/env node
// capture.mjs: reference screenshot capture for the visual-evidence skill.
// Drives a self-launched headless Chrome over raw CDP (no npm dependencies;
// Node 22+ for the built-in WebSocket client, Chrome 112+ for
// --headless=new) with the determinism the skill's prose asks for:
// real readiness waits (networkIdle lifecycle event, selector visibility),
// an animation kill switch, a viewport matrix, element-level clipping,
// retries, and a total timeout budget that fails fast and loud instead of
// letting an agent's shell cap kill the command opaquely.
//
// Usage:
//   node capture.mjs --url <http|https|file URL> --out <path.png>
//     [--viewport 1280x720[,390x844,...]]  # comma list; default 1280x720
//     [--wait-for '<css selector>']  # wait until present AND visible
//     [--clip '<css selector>']      # crop to the element's bounding box
//     [--clip-pad 12]                # px context padding around --clip
//     [--settle-ms 500]              # quiet period after readiness
//     [--dpr 2]                      # device pixel ratio (1-4)
//     [--dark]                       # emulate prefers-color-scheme: dark
//     [--timeout-budget 90]          # TOTAL seconds, all viewports+retries
//     [--attempt-timeout 30]         # per-attempt seconds (clamped to
//                                    # the remaining budget)
//     [--retries 2]                  # extra attempts per viewport
//     [--chrome <path>]              # binary override (also $CHROME env)
//     [--chrome-flag <flag>]         # repeatable extra Chrome flag (e.g.
//                                    # --no-sandbox in containers)
//
// One viewport writes exactly --out; multiple viewports insert the size
// before the extension (before.png -> before-1280x720.png). One summary
// line per file on stdout:
//   WROTE <path> viewport=<WxH> image=<WxH> bytes=<n>
// so the caller can run the skill's dimension sanity check without extra
// tooling. Widths <= 600 get Chrome's mobile emulation.
//
// Exit codes: 0 all viewports captured; 1 capture failed after
// retries/budget; 64 usage error; 69 Chrome (or Node's WebSocket) missing,
// with the skill's prose guidance as the fallback.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

const WS_ENDPOINT_TIMEOUT_MS = 20000; // clamped to the remaining budget
const NETWORK_IDLE_GRACE_MS = 5000; // after load, for long-polling pages
const SELECTOR_POLL_MS = 150;

const USAGE_END = 'with the skill\'s prose guidance as the fallback.';

function usage(message) {
  if (message) process.stderr.write(`capture.mjs: ${message}\n`);
  const self = fs.readFileSync(new URL(import.meta.url), 'utf8');
  const end = self.indexOf(USAGE_END);
  const header = self
    .slice(0, self.indexOf('\n', end) + 1)
    .split('\n')
    .filter((l) => l.startsWith('//'))
    .map((l) => l.replace(/^\/\/ ?/, ''))
    .join('\n');
  process.stderr.write(header + '\n');
  process.exit(64);
}

// ---- argument parsing & validation (no side effects, exit 64) ----------

function parseArgs(argv) {
  const valued = new Set([
    '--url',
    '--out',
    '--viewport',
    '--wait-for',
    '--clip',
    '--clip-pad',
    '--settle-ms',
    '--dpr',
    '--timeout-budget',
    '--attempt-timeout',
    '--retries',
    '--chrome',
    '--chrome-flag',
  ]);
  const raw = {
    viewport: '1280x720',
    clipPad: '12',
    settleMs: '500',
    dpr: '2',
    timeoutBudget: '90',
    attemptTimeout: '30',
    retries: '2',
    chromeFlags: [],
    dark: false,
  };
  const keyOf = {
    '--url': 'url',
    '--out': 'out',
    '--viewport': 'viewport',
    '--wait-for': 'waitFor',
    '--clip': 'clip',
    '--clip-pad': 'clipPad',
    '--settle-ms': 'settleMs',
    '--dpr': 'dpr',
    '--timeout-budget': 'timeoutBudget',
    '--attempt-timeout': 'attemptTimeout',
    '--retries': 'retries',
    '--chrome': 'chrome',
  };
  let i = 0;
  // Recognize the option, then require its value, before reading the next
  // token: a trailing bare option must die as a usage error.
  while (i < argv.length) {
    const opt = argv[i];
    if (opt === '--dark') {
      raw.dark = true;
      i += 1;
      continue;
    }
    if (!valued.has(opt)) usage(`unknown option: ${opt}`);
    if (i + 1 >= argv.length) usage(`${opt} requires a value`);
    const val = argv[i + 1];
    if (opt === '--chrome-flag') raw.chromeFlags.push(val);
    else raw[keyOf[opt]] = val;
    i += 2;
  }

  if (!raw.url) usage('--url is required');
  if (!raw.out) usage('--out is required');

  let url;
  try {
    url = new URL(raw.url);
  } catch {
    usage(`--url is not a valid URL: ${raw.url}`);
  }
  if (!['http:', 'https:', 'file:'].includes(url.protocol))
    usage(`--url scheme must be http, https, or file (got ${url.protocol})`);

  if (!raw.out.endsWith('.png')) usage('--out must end in .png');

  const viewports = raw.viewport.split(',').map((spec) => {
    const m = /^(\d+)x(\d+)$/.exec(spec);
    if (!m) usage(`--viewport entries must be WxH (got "${spec}")`);
    const width = Number(m[1]);
    const height = Number(m[2]);
    if (width < 16 || width > 8192 || height < 16 || height > 8192)
      usage(`--viewport dimensions must be 16-8192 (got "${spec}")`);
    return { spec, width, height };
  });

  const posInt = (name, v) => {
    if (!/^\d+$/.test(v) || Number(v) === 0)
      usage(`${name} must be a positive integer (got "${v}")`);
    return Number(v);
  };
  const nonNegInt = (name, v) => {
    if (!/^\d+$/.test(v)) usage(`${name} must be a non-negative integer (got "${v}")`);
    return Number(v);
  };

  if (!/^[1-4]$/.test(raw.dpr)) usage(`--dpr must be 1-4 (got "${raw.dpr}")`);
  if (raw.waitFor !== undefined && raw.waitFor === '')
    usage('--wait-for requires a non-empty selector');
  if (raw.clip !== undefined && raw.clip === '')
    usage('--clip requires a non-empty selector');
  if (argv.includes('--clip-pad') && raw.clip === undefined)
    usage('--clip-pad only makes sense with --clip');
  for (const f of raw.chromeFlags)
    if (!f.startsWith('-')) usage(`--chrome-flag values must be flags (got "${f}")`);

  return {
    url: url.href,
    out: raw.out,
    viewports,
    waitFor: raw.waitFor,
    clip: raw.clip,
    clipPad: nonNegInt('--clip-pad', raw.clipPad),
    settleMs: posInt('--settle-ms', raw.settleMs),
    dpr: Number(raw.dpr),
    dark: raw.dark,
    budgetMs: posInt('--timeout-budget', raw.timeoutBudget) * 1000,
    attemptMs: posInt('--attempt-timeout', raw.attemptTimeout) * 1000,
    retries: nonNegInt('--retries', raw.retries),
    chrome: raw.chrome || process.env.CHROME || '',
    chromeFlags: raw.chromeFlags,
  };
}

// ---- Chrome discovery (exit 69) -----------------------------------------

function isExecutable(p) {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

function die69(message) {
  process.stderr.write(
    `capture.mjs: ${message}; cannot capture, use the skill's prose capture guidance with your environment's own tooling\n`,
  );
  process.exit(69);
}

function discoverChrome(explicit) {
  if (explicit) {
    if (isExecutable(explicit)) return explicit;
    die69(`Chrome not found at ${explicit} (--chrome / $CHROME)`);
  }
  const fixed = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
  ];
  for (const p of fixed) if (isExecutable(p)) return p;
  const names = ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser'];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    for (const name of names) {
      const p = path.join(dir, name);
      if (isExecutable(p)) return p;
    }
  }
  die69('Chrome not found (checked --chrome, $CHROME, macOS app paths, PATH)');
}

// ---- CDP client over Node's built-in WebSocket ---------------------------

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    this.events = [];
    this.waiters = new Set();
    ws.addEventListener('message', (ev) => this.onMessage(String(ev.data)));
    ws.addEventListener('close', () => this.onClose());
    ws.addEventListener('error', () => this.onClose());
  }

  send(method, params = {}, sessionId) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject, method });
      this.ws.send(JSON.stringify({ id, method, params, ...(sessionId && { sessionId }) }));
    });
  }

  onMessage(text) {
    let msg;
    try {
      msg = JSON.parse(text);
    } catch {
      return;
    }
    if (msg.id !== undefined) {
      const p = this.pending.get(msg.id);
      if (!p) return;
      this.pending.delete(msg.id);
      if (msg.error) p.reject(new Error(`${p.method}: ${msg.error.message}`));
      else p.resolve(msg.result);
      return;
    }
    this.events.push(msg);
    if (this.events.length > 2000) this.events.shift();
    for (const w of [...this.waiters]) {
      if (w.match(msg)) {
        this.waiters.delete(w);
        clearTimeout(w.timer);
        w.resolve(msg);
      }
    }
  }

  onClose() {
    const err = new Error('DevTools connection closed');
    for (const p of this.pending.values()) p.reject(err);
    this.pending.clear();
    for (const w of this.waiters) {
      clearTimeout(w.timer);
      w.reject(err);
    }
    this.waiters.clear();
  }

  // Resolve with the first event matching `match`, scanning the buffer of
  // already-received events first so an event racing the caller isn't lost.
  waitEvent(match, deadline, label) {
    const buffered = this.events.find(match);
    if (buffered) return Promise.resolve(buffered);
    return new Promise((resolve, reject) => {
      const w = { match, resolve, reject };
      w.timer = setTimeout(() => {
        this.waiters.delete(w);
        reject(new Error(`timed out waiting for ${label}`));
      }, Math.max(1, deadline - Date.now()));
      this.waiters.add(w);
    });
  }
}

function raced(promise, deadline, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`timed out during ${label}`)),
      Math.max(1, deadline - Date.now()),
    );
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- Chrome launch --------------------------------------------------------

function launchChrome(chrome, extraFlags, deadline) {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'capture-mjs-'));
  const child = spawn(
    chrome,
    [
      '--headless=new',
      '--remote-debugging-port=0',
      `--user-data-dir=${profile}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--use-mock-keychain',
      '--hide-scrollbars',
      '--disable-gpu',
      '--mute-audio',
      ...extraFlags,
      'about:blank',
    ],
    { stdio: ['ignore', 'ignore', 'pipe'] },
  );
  const endpoint = new Promise((resolve, reject) => {
    let buf = '';
    let settled = false;
    const done = (fn, arg) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn(arg);
    };
    const timer = setTimeout(
      () =>
        done(
          reject,
          new Error('Chrome did not report its DevTools endpoint in time'),
        ),
      Math.max(1, Math.min(WS_ENDPOINT_TIMEOUT_MS, deadline - Date.now())),
    );
    child.stderr.on('data', (chunk) => {
      buf += chunk;
      const m = /DevTools listening on (ws:\/\/\S+)/.exec(buf);
      if (m) done(resolve, m[1]);
    });
    child.on('error', (err) => done(reject, new Error(`Chrome failed to start: ${err.message}`)));
    child.on('exit', (code, signal) => {
      const tail = buf.trim().split('\n').slice(-3).join(' | ');
      done(
        reject,
        new Error(
          `Chrome exited before it was ready (${signal || `code ${code}`})` +
            `${tail ? `: ${tail}` : ''}` +
            ' (in containers, try --chrome-flag --no-sandbox)',
        ),
      );
    });
  });
  return { child, profile, endpoint };
}

// ---- capture --------------------------------------------------------------

// Kill animations at document start so timer-driven visual churn never
// begins; the style survives navigations via addScriptToEvaluateOnNewDocument.
const KILL_ANIMATIONS = `(() => {
  const add = () => {
    const s = document.createElement('style');
    s.textContent = '*,*::before,*::after{animation:none!important;transition:none!important;scroll-behavior:auto!important;caret-color:transparent!important}';
    (document.head || document.documentElement).appendChild(s);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add);
  else if (document.documentElement) add();
})();`;

async function evalIn(cdp, sessionId, expression, deadline, label, awaitPromise = false) {
  const res = await raced(
    cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise }, sessionId),
    deadline,
    label,
  );
  if (res.exceptionDetails)
    throw new Error(`${label}: ${res.exceptionDetails.text || 'page threw'}`);
  return res.result.value;
}

async function waitReadiness(cdp, sessionId, frameId, loaderId, deadline) {
  const lifecycle = (name) => (m) =>
    m.method === 'Page.lifecycleEvent' &&
    m.sessionId === sessionId &&
    m.params.frameId === frameId &&
    m.params.loaderId === loaderId &&
    m.params.name === name;
  const idle = cdp.waitEvent(lifecycle('networkIdle'), deadline, 'networkIdle');
  // Long-polling and websocket pages never reach networkIdle; once load has
  // fired, a bounded grace period is the deterministic fallback, so a hung
  // wait becomes a retry instead of eating the whole budget.
  const loadThenGrace = cdp
    .waitEvent(lifecycle('load'), deadline, 'load')
    .then(() => sleep(Math.max(0, Math.min(NETWORK_IDLE_GRACE_MS, deadline - Date.now()))));
  idle.catch(() => {});
  loadThenGrace.catch(() => {});
  try {
    await Promise.any([idle, loadThenGrace]);
  } catch {
    throw new Error('page never reached load within the attempt timeout');
  }
}

async function attemptCapture(cdp, sessionId, cfg, vp, outPath, deadline) {
  await raced(
    cdp.send(
      'Emulation.setDeviceMetricsOverride',
      {
        width: vp.width,
        height: vp.height,
        deviceScaleFactor: cfg.dpr,
        mobile: vp.width <= 600,
      },
      sessionId,
    ),
    deadline,
    'viewport override',
  );
  // Always pin the color scheme: headless Chrome inherits the host OS
  // theme, so an unpinned capture is light on one machine and dark on
  // another. Explicit emulation keeps the pair deterministic.
  await raced(
    cdp.send(
      'Emulation.setEmulatedMedia',
      { features: [{ name: 'prefers-color-scheme', value: cfg.dark ? 'dark' : 'light' }] },
      sessionId,
    ),
    deadline,
    'color-scheme emulation',
  );

  const nav = await raced(
    cdp.send('Page.navigate', { url: cfg.url }, sessionId),
    deadline,
    'navigation',
  );
  if (nav.errorText) throw new Error(`navigation failed: ${nav.errorText}`);
  await waitReadiness(cdp, sessionId, nav.frameId, nav.loaderId, deadline);

  if (cfg.waitFor) {
    const visible = `(() => {
      const el = document.querySelector(${JSON.stringify(cfg.waitFor)});
      if (!el) return false;
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none';
    })()`;
    for (;;) {
      if (await evalIn(cdp, sessionId, visible, deadline, '--wait-for check')) break;
      if (Date.now() + SELECTOR_POLL_MS >= deadline)
        throw new Error(`--wait-for selector never became visible: ${cfg.waitFor}`);
      await sleep(SELECTOR_POLL_MS);
    }
    // Two animation frames so layout from the just-appeared element settles.
    await evalIn(
      cdp,
      sessionId,
      'new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r(true))))',
      deadline,
      'frame settle',
      true,
    );
  }

  if (Date.now() + cfg.settleMs >= deadline)
    throw new Error('attempt timeout during settle period');
  await sleep(cfg.settleMs);

  let clip;
  if (cfg.clip) {
    // Clip coordinates live in the page's layout space, which is NOT the
    // emulated device size when mobile emulation scales a viewport-meta-less
    // page (a 390px device lays out at ~980px). Measure the document's own
    // bounds in the same evaluate and clamp against those.
    const rectJson = await evalIn(
      cdp,
      sessionId,
      `(() => {
        const el = document.querySelector(${JSON.stringify(cfg.clip)});
        if (!el) return null;
        el.scrollIntoView({ block: 'center', inline: 'center' });
        const r = el.getBoundingClientRect();
        const d = document.documentElement;
        return JSON.stringify({
          x: r.x + window.scrollX, y: r.y + window.scrollY,
          width: r.width, height: r.height,
          docW: Math.max(d.scrollWidth, d.clientWidth),
          docH: Math.max(d.scrollHeight, d.clientHeight),
        });
      })()`,
      deadline,
      '--clip lookup',
    );
    if (!rectJson) throw new Error(`--clip selector matched nothing: ${cfg.clip}`);
    const r = JSON.parse(rectJson);
    const x = Math.max(0, r.x - cfg.clipPad);
    const y = Math.max(0, r.y - cfg.clipPad);
    const width = Math.min(r.docW - x, r.width + 2 * cfg.clipPad);
    const height = Math.min(r.docH - y, r.height + 2 * cfg.clipPad);
    if (width <= 0 || height <= 0)
      throw new Error(`--clip element has no measurable area: ${cfg.clip}`);
    clip = { x, y, width, height, scale: 1 };
  }

  // captureBeyondViewport lets a clip cover an element taller or wider than
  // the viewport instead of cutting it at the fold.
  const shot = await raced(
    cdp.send(
      'Page.captureScreenshot',
      { format: 'png', ...(clip && { clip, captureBeyondViewport: true }) },
      sessionId,
    ),
    deadline,
    'screenshot',
  );
  const bytes = Buffer.from(shot.data, 'base64');
  if (bytes.length === 0) throw new Error('screenshot came back empty');
  fs.writeFileSync(outPath, bytes);
  // PNG IHDR: width and height are big-endian u32 at offsets 16 and 20.
  const imgW = bytes.readUInt32BE(16);
  const imgH = bytes.readUInt32BE(20);
  if (imgW === 0 || imgH === 0) throw new Error('screenshot has a zero dimension');
  process.stdout.write(
    `WROTE ${outPath} viewport=${vp.spec} image=${imgW}x${imgH} bytes=${bytes.length}\n`,
  );
}

// ---- main -----------------------------------------------------------------

async function main() {
  const cfg = parseArgs(process.argv.slice(2));
  const outDir = path.dirname(cfg.out);
  if (!fs.existsSync(outDir)) usage(`output directory does not exist: ${outDir}`);
  if (typeof WebSocket === 'undefined')
    die69('this Node lacks the built-in WebSocket client (need Node 22+)');
  const chrome = discoverChrome(cfg.chrome);

  const globalDeadline = Date.now() + cfg.budgetMs;
  let child;
  let profile = '';

  const cleanup = async () => {
    if (child && child.exitCode === null && !child.killed) {
      child.kill('SIGTERM');
      const gone = new Promise((r) => child.once('exit', r));
      await Promise.race([gone, sleep(1500)]);
      if (child.exitCode === null) child.kill('SIGKILL');
    }
    if (profile) fs.rmSync(profile, { recursive: true, force: true });
  };
  const fail = async (message) => {
    process.stderr.write(`capture.mjs: ${message}\n`);
    await cleanup();
    process.exit(1);
  };

  // Backstop: even if some wait slips past its deadline, the process must
  // exit on its own terms before an agent's shell cap kills it opaquely.
  const watchdog = setTimeout(
    () => fail(`timeout budget (${cfg.budgetMs / 1000}s) exhausted; aborting`),
    cfg.budgetMs + 2000,
  );
  process.on('SIGINT', () => fail('interrupted'));
  process.on('SIGTERM', () => fail('terminated'));

  try {
    const launched = launchChrome(chrome, cfg.chromeFlags, globalDeadline);
    child = launched.child;
    profile = launched.profile;
    const wsUrl = await launched.endpoint;

    const ws = await raced(
      new Promise((resolve, reject) => {
        const sock = new WebSocket(wsUrl);
        sock.addEventListener('open', () => resolve(sock));
        sock.addEventListener('error', () => reject(new Error('DevTools WebSocket failed')));
      }),
      globalDeadline,
      'DevTools connect',
    );
    const cdp = new Cdp(ws);

    const { targetId } = await raced(
      cdp.send('Target.createTarget', { url: 'about:blank' }),
      globalDeadline,
      'target create',
    );
    const { sessionId } = await raced(
      cdp.send('Target.attachToTarget', { targetId, flatten: true }),
      globalDeadline,
      'target attach',
    );
    await raced(cdp.send('Page.enable', {}, sessionId), globalDeadline, 'Page.enable');
    await raced(cdp.send('Runtime.enable', {}, sessionId), globalDeadline, 'Runtime.enable');
    await raced(
      cdp.send('Page.setLifecycleEventsEnabled', { enabled: true }, sessionId),
      globalDeadline,
      'lifecycle enable',
    );
    await raced(
      cdp.send('Page.addScriptToEvaluateOnNewDocument', { source: KILL_ANIMATIONS }, sessionId),
      globalDeadline,
      'animation kill install',
    );

    const many = cfg.viewports.length > 1;
    for (const vp of cfg.viewports) {
      const outPath = many ? cfg.out.replace(/\.png$/, `-${vp.spec}.png`) : cfg.out;
      const attempts = 1 + cfg.retries;
      let lastError;
      let done = false;
      for (let attempt = 1; attempt <= attempts && !done; attempt++) {
        const deadline = Math.min(Date.now() + cfg.attemptMs, globalDeadline);
        try {
          await attemptCapture(cdp, sessionId, cfg, vp, outPath, deadline);
          done = true;
        } catch (err) {
          lastError = err;
          if (Date.now() >= globalDeadline - 1000)
            throw new Error(
              `viewport ${vp.spec} attempt ${attempt}/${attempts} failed (${err.message}) with the budget exhausted`,
            );
          if (attempt < attempts) {
            process.stderr.write(
              `capture.mjs: viewport ${vp.spec} attempt ${attempt}/${attempts} failed: ${err.message}; retrying\n`,
            );
            await cdp
              .send('Page.navigate', { url: 'about:blank' }, sessionId)
              .catch(() => {});
          }
        }
      }
      if (!done)
        throw new Error(
          `viewport ${vp.spec} failed after ${attempts} attempt(s): ${lastError.message}`,
        );
    }

    clearTimeout(watchdog);
    await cleanup();
    process.exit(0);
  } catch (err) {
    clearTimeout(watchdog);
    await fail(err.message);
  }
}

main();
