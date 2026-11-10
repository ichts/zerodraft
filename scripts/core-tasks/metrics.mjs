/* Core tasks, the numbers behind the scorecard.
   [INPUT] raw runs from `measure-web.mjs` (one entry per browser run, already timestamped in the page) and, for
           comparison, two metrics documents in the shape `data/wid-core-tasks-baseline` uses, so the captain's own
           `core-tasks.py compare` reads these files too.
   [OUTPUT] `runsToMetrics` (one entry per task and platform: steps, the sum of the product's own latencies, the
           segments it summed, and the run count), `experienceLines` (the report.md line format: task name,
           platform, before and after, fewer steps, and "within noise" inside 5% or 50 ms), and `formatTable`.
   [POS] pure, browser-free, and the only place the scorecard's wording and noise rule live; the meter and the
         tests both read it. Nothing here measures anything, so it is deterministic and needs no clock.
   [PROTOCOL] T1 Begin to writing, T2 Finish to text, T3 Buy to checkout, and these names are the report format.
              A value that was not measured is null and never estimated. Human think time is never included. */

export const TASK_NAMES = { T1: 'Begin to writing', T2: 'Finish to text', T3: 'Buy to checkout', T3b: 'Buy to checkout (header path)' };
const NOISE_FLOOR_MS = 50;
const NOISE_SHARE = 0.05;

/* The lower median of an even count, the same rule the baseline harness uses: report a number that was measured. */
export function median(values) {
  const xs = values.filter(x => x != null).sort((a, b) => a - b);
  return xs.length ? xs[Math.floor((xs.length - 1) / 2)] : null;
}

export function fmtMs(ms) {
  if (ms == null) return 'time unmeasured';
  return ms >= 1000 ? `${(ms / 1000).toFixed(2)} s` : `${Math.round(ms)} ms`;
}

const sum = segments => {
  const values = Object.values(segments);
  return values.some(v => v == null) ? null : Math.round(values.reduce((a, b) => a + b, 0) * 10) / 10;
};
const pick = (runs, read) => median(runs.map(read));

/* Raw runs -> the metrics document. A task with no run in this measurement is left out rather than filled with a
   guess, and a step count is the number of actions a person must take, which the meter knows by construction. */
export function runsToMetrics(runs, meta) {
  const out = { meta: { ...meta, runs: runs.length } };
  for (const viewport of [...new Set(runs.map(r => r.viewport))].sort()) {
    const rs = runs.filter(r => r.viewport === viewport);
    const key = `web-${viewport}`;
    const m = {};
    const t1 = rs.filter(r => r.t1);
    if (t1.length) {
      const segments = {
        nav_to_fonts_ready: pick(t1, r => r.t1.ms.nav_to_fonts_ready),
        click_to_editor_focus: pick(t1, r => r.t1.ms.click_to_editor_focus),
        key_to_glyph_painted: pick(t1, r => r.t1.ms.key_to_glyph_painted)
      };
      m.T1 = { steps: 2, steps_detail: '1 click (Give it 60 seconds) + 1 key', ms: sum(segments), segments_ms: segments, n: t1.length };
    }
    const t2 = rs.filter(r => r.t2);
    if (t2.length) {
      const segments = {
        first_char_to_kept_painted: pick(t2, r => r.t2.ms.first_char_to_kept_painted),
        copy_pointer_to_copied_label: pick(t2, r => r.t2.ms.copy_pointer_to_copied_label)
      };
      m.T2 = {
        steps: 2,
        steps_detail: `1 uninterrupted write + 1 click (Copy text); typing keystrokes ${pick(t2, r => r.t2.steps.typingKeystrokes)}`,
        ms: sum(segments),
        segments_ms: {
          ...segments,
          deadline_overrun_vs_60000: pick(t2, r => r.t2.ms.deadline_overrun_vs_60000),
          deadline_detection_ms: pick(t2, r => r.t2.ms.deadline_detection_ms),
          kept_paint_ms: pick(t2, r => r.t2.ms.kept_paint_ms)
        },
        n: t2.length,
        checks: { kept_matches_typed: t2.every(r => r.t2.keptTextMatchesTyped), clipboard_matches_kept: t2.every(r => r.t2.clipboardMatchesKept) }
      };
    }
    const t3 = rs.filter(r => r.t3);
    if (t3.length) {
      const segments = {
        landing_click_to_purchase_page_loaded: pick(t3, r => r.t3.ms.landing_click_to_purchase_page_loaded),
        buy_click_to_stripe_handoff: pick(t3, r => r.t3.ms.buy_click_to_stripe_handoff)
      };
      const purchaseScreens = pick(t3, r => r.t3.purchase?.screens ?? null);
      const purchaseOnFirst = t3.every(r => r.t3.purchase?.buyInFirstScreen);
      m.T3 = {
        steps: 2,
        steps_detail: `2 clicks + ${pick(t3, r => r.t3.reach.screensDown)} screens of scrolling to find the landing Buy link;`
          + (purchaseScreens == null ? ' purchase page unmeasured'
            : ` the purchase page is ${purchaseScreens} screen${purchaseScreens === 1 ? '' : 's'} and its Buy control ${purchaseOnFirst ? 'is on the first screen' : 'needs scrolling'}`),
        ms: sum(segments),
        segments_ms: segments,
        n: t3.length,
        reach_screens_down: pick(t3, r => r.t3.reach.screensDown),
        in_first_screen: t3.every(r => r.t3.reach.inFirstScreen),
        purchase_page_screens: purchaseScreens,
        purchase_buy_on_first_screen: purchaseScreens == null ? null : purchaseOnFirst
      };
    }
    const t3b = rs.filter(r => r.t3b);
    if (t3b.length) {
      m.T3b = { steps: 3, steps_detail: '3 clicks, no scrolling (header Download for Mac -> Buy for $4.99 once -> Buy)', ms: pick(t3b, r => r.t3b.ms.total_machine), n: t3b.length };
    }
    m.load_avg_runs = rs.map(r => Math.round(r.loadavg));
    out[key] = m;
  }
  return out;
}

/* The one line per task and platform the captain reads. Steps always show; time only claims a change outside the
   noise floor (5% or 50 ms, whichever is larger), because a loaded host moves milliseconds every run. */
export function experienceLines(oldMetrics, newMetrics) {
  const lines = [];
  for (const [platform, after] of Object.entries(newMetrics)) {
    if (platform.startsWith('_') || platform === 'meta' || !oldMetrics[platform]) continue;
    for (const task of ['T1', 'T2', 'T3']) {
      const before = oldMetrics[platform][task];
      const now = after[task];
      if (!before || !now) continue;
      const delta = before.steps - now.steps;
      const steps = delta ? `${Math.abs(delta)} ${delta > 0 ? 'fewer' : 'more'} steps` : '0 fewer steps';
      let time;
      if (before.ms == null || now.ms == null) time = 'time unmeasured';
      else if (Math.abs(now.ms - before.ms) <= Math.max(NOISE_SHARE * before.ms, NOISE_FLOOR_MS)) time = `${fmtMs(before.ms)} to ${fmtMs(now.ms)} (within noise)`;
      else time = `${fmtMs(before.ms)} to ${fmtMs(now.ms)}`;
      lines.push(`${TASK_NAMES[task]} (${platform}): ${time}, ${steps}`);
    }
  }
  return lines.length ? lines : 'No measurable change in the three core tasks.';
}

export function formatTable(metrics) {
  const rows = [['task', 'platform', 'steps', 'machine time', 'note']];
  for (const [platform, m] of Object.entries(metrics)) {
    if (platform.startsWith('_') || platform === 'meta') continue;
    for (const task of ['T1', 'T2', 'T3', 'T3b']) {
      const t = m[task];
      if (!t) continue;
      const note = [];
      if (task === 'T2' && t.segments_ms) note.push(`deadline +${t.segments_ms.deadline_overrun_vs_60000} ms (detection ${t.segments_ms.deadline_detection_ms}, paint ${t.segments_ms.kept_paint_ms})`);
      if (task === 'T3' && t.reach_screens_down != null) note.push(`${t.reach_screens_down} screens down; first screen: ${t.in_first_screen ? 'yes' : 'no'}`);
      if (t.checks) note.push(...Object.entries(t.checks).map(([k, v]) => `${k}: ${v ? 'yes' : 'NO'}`));
      const steps = t.steps_detail ? `${t.steps} (${t.steps_detail})` : String(t.steps);
      rows.push([`${task} ${TASK_NAMES[task] ?? ''}`.trim(), platform, steps, fmtMs(t.ms), note.join('; ')]);
    }
  }
  const widths = rows[0].map((_, i) => Math.max(...rows.map(r => (r[i] ?? '').length)));
  return rows.map(r => '| ' + r.map((c, i) => (c ?? '').padEnd(widths[i])).join(' | ') + ' |').join('\n');
}
