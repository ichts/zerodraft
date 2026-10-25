#!/usr/bin/env python3
"""Helpers for the design panel report.

[INPUT] `extract` reads a model answer on stdin and returns the first JSON object
        in it. `report` reads <evidence>/panel/panel.json plus the thumbnails the
        panel script wrote and renders <evidence>/panel/report.html.
[OUTPUT] Either the extracted JSON on stdout, or a self-contained static HTML
         report whose images are inlined, so the bundle can be read on its own.
[POS] apps/macos/FirstLine/scripts/vm/panel-lib.py - the small, boring part of
      design-panel.sh: model-answer parsing and report rendering.
[PROTOCOL] Report rendering never invents content: a stage that did not run is
           rendered as a declared gap with its recorded reason, and a lens with no
           answer is rendered as unavailable rather than omitted.
"""

import base64
import html
import json
import os
import re
import sys

SEVERITY_ORDER = {"blocker": 0, "major": 1, "minor": 2, "nit": 3, "info": 4}


def extract():
    text = sys.stdin.read()
    fenced = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    candidate = fenced.group(1) if fenced else text
    start = candidate.find("{")
    while start != -1:
        depth = 0
        for index in range(start, len(candidate)):
            char = candidate[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    chunk = candidate[start:index + 1]
                    try:
                        print(json.dumps(json.loads(chunk), sort_keys=True))
                        return 0
                    except json.JSONDecodeError:
                        break
        start = candidate.find("{", start + 1)
    print("panel-lib: no JSON object in the model answer", file=sys.stderr)
    return 1


def image(panel_dir, name, max_height=320):
    path = os.path.join(panel_dir, "thumbs", name)
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as handle:
        encoded = base64.b64encode(handle.read()).decode("ascii")
    return (f'<img style="max-height:{max_height}px;max-width:100%;border:1px solid #d8d6cf;'
            f'border-radius:3px" src="data:image/jpeg;base64,{encoded}" alt="{html.escape(name)}">')


def esc(value):
    return html.escape(str(value if value is not None else ""))


def severity_badge(severity):
    tones = {"blocker": "#8d2b22", "major": "#b3541e", "minor": "#6b6455", "nit": "#8a8578",
             "info": "#6b6455", "high": "#8d2b22", "low": "#6b6455"}
    colour = tones.get((severity or "").lower(), "#6b6455")
    return (f'<span style="display:inline-block;padding:1px 6px;border:1px solid {colour};'
            f'color:{colour};border-radius:999px;font:600 10px/1.6 ui-monospace,Menlo,monospace;'
            f'letter-spacing:.06em;text-transform:uppercase">{esc(severity or "info")}</span>')


def render_findings(findings, panel_dir):
    if not findings:
        return "<p class=muted>No deterministic findings were recorded for this run.</p>"
    rows = []
    ordered = sorted(findings, key=lambda f: (SEVERITY_ORDER.get((f.get("severity") or "").lower(), 9),
                                              f.get("t_start") or 0))
    for finding in ordered:
        window = ""
        if finding.get("t_start"):
            window = f'{finding["t_start"]} &rarr; {finding.get("t_end", "")}'
        thumbs = "".join(image(panel_dir, f'frame-{finding["t_start"]}-{index}.jpg')
                         for index in range(6))
        rows.append(f"""<tr><td>{severity_badge(finding.get('severity'))}</td>
<td><code>{esc(finding.get('kind'))}</code><br><code>{esc(finding.get('assertion') or 'informational')}</code></td>
<td>{esc(finding.get('note'))}<br><span class=muted>{esc(window)} &middot; {esc(finding.get('duration_ms'))} ms</span></td>
<td class=shots>{thumbs}</td></tr>""")
    return ("<table><thead><tr><th>Severity</th><th>Kind / assertion</th><th>What the analysis saw</th>"
            "<th>Frames</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


def render_clip_reviews(reviews, panel_dir):
    if not reviews:
        return "<p class=muted>No flagged clips were reviewed.</p>"
    blocks = []
    for review in reviews:
        thumbs = "".join(image(panel_dir, name) for name in review.get("frames", []))
        blocks.append(f"""<div class=card>
<h3>{severity_badge(review.get('verdict'))} {esc(review.get('window'))}</h3>
<p>{esc(review.get('reason'))}</p>
<p class=muted>model: <code>{esc(review.get('model'))}</code></p>
<div class=shots>{thumbs}</div>
<details><summary>exact command</summary><pre>{esc(review.get('command'))}</pre></details>
</div>""")
    return "".join(blocks)


def render_vision_checks(checks):
    if not checks:
        return "<p class=muted>The vision checker did not run.</p>"
    rows = []
    for check in checks:
        state = "still valid" if check.get("next_step_valid") else "needs a look"
        rows.append(f"""<tr><td>{esc(check.get('transition'))}</td><td>{esc(check.get('next_step'))}</td>
<td>{esc(state)}</td><td><code>{esc(check.get('check_step_index'))}</code></td>
<td class=muted>{esc(check.get('reason'))}</td></tr>""")
    return ("<p>The checker judges whether the shots after a UI change still support the scripted next "
            "step. It reports the index of the next step that needs a visual check; it never chooses an "
            "action.</p><table><thead><tr><th>Transition</th><th>Scripted next step</th><th>Verdict</th>"
            "<th>Check step</th><th>Why</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


def render_lenses(lenses, panel_dir):
    if not lenses:
        return "<p class=muted>No lens reviews were recorded.</p>"
    blocks = []
    for lens in lenses:
        state = lens.get("status")
        header = f"<h2>{esc(lens.get('lens'))}</h2>"
        if state != "complete":
            detail = lens.get("error") or "no answer recorded"
            blocks.append(f"<div class=card>{header}<p>{severity_badge('info')} "
                          f"<span class=muted>this lens did not run: {esc(detail)}</span></p>"
                          f"<details><summary>exact command</summary><pre>{esc(lens.get('command'))}</pre>"
                          f"</details></div>")
            continue
        answer = lens.get("answer") or {}
        findings = sorted(answer.get("findings") or [],
                          key=lambda f: SEVERITY_ORDER.get((f.get("severity") or "").lower(), 9))
        items = []
        for finding in findings:
            reference = finding.get("evidence") or ""
            thumb = ""
            if reference.endswith(".png"):
                thumb = image(panel_dir, os.path.basename(reference))
            items.append(f"""<div class=finding>{severity_badge(finding.get('severity'))}
<strong>{esc(finding.get('title'))}</strong>
<div>{esc(finding.get('why'))}</div>
{f'<div class=muted>fix: {esc(finding.get("fix"))}</div>' if finding.get('fix') else ''}
{f'<div class=muted>evidence: <code>{esc(reference)}</code></div>' if reference else ''}
{f'<div class=muted>drift: {esc(finding.get("agrees_with_step"))}</div>' if finding.get('agrees_with_step') else ''}
{thumb}</div>""")
        summary = esc(answer.get("summary") or "")
        blocks.append(f"""<div class=card>{header}
<p>{severity_badge(answer.get('verdict') or 'info')} {summary}</p>
{''.join(items) or '<p class=muted>no findings</p>'}
<p class=muted>model: <code>{esc(lens.get('model'))}</code></p>
<details><summary>exact command</summary><pre>{esc(lens.get('command'))}</pre></details></div>""")
    return "".join(blocks)


def render_capabilities(capabilities):
    rows = []
    for capability in capabilities:
        colour = "#3f6b3f" if capability.get("status") == "complete" else "#b3541e"
        rows.append(f"""<tr><td>{esc(capability.get('stage'))}</td>
<td><span style="color:{colour};font-weight:600">{esc(capability.get('status'))}</span></td>
<td>{esc(capability.get('model') or capability.get('route') or '')}</td>
<td class=muted>{esc(capability.get('detail'))}</td></tr>""")
    return ("<table><thead><tr><th>Stage</th><th>Status</th><th>Model / route</th><th>Detail</th>"
            "</tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


def report():
    evidence = os.path.abspath(sys.argv[2])
    panel_dir = os.path.join(evidence, "panel")
    with open(os.path.join(panel_dir, "panel.json"), encoding="utf-8") as handle:
        panel = json.load(handle)

    css = """
    :root { color-scheme: light }
    body { margin:0; padding:40px 32px 72px; background:#f1f0eb; color:#1c1b19;
      font:400 15px/1.6 "Newsreader", Georgia, serif }
    h1 { font-size:30px; line-height:1.15; margin:0 0 6px }
    h2 { font-size:20px; margin:28px 0 8px }
    h3 { font-size:15px; margin:0 0 8px }
    code, pre, table.mono { font-family: ui-monospace, "IBM Plex Mono", Menlo, monospace }
    code { font-size:12px }
    .muted { color:#6b6455 }
    .card { background:#fff; border:1px solid #e2e0d8; border-radius:4px; padding:16px 18px; margin:12px 0 }
    table { width:100%; border-collapse:collapse; background:#fff; border:1px solid #e2e0d8; margin:8px 0 16px }
    th, td { text-align:left; vertical-align:top; padding:8px 10px; border-bottom:1px solid #eeece5; font-size:13px }
    th { font:600 11px/1.5 ui-monospace,Menlo,monospace; letter-spacing:.08em; text-transform:uppercase; color:#6b6455 }
    .shots { display:flex; gap:6px; flex-wrap:wrap }
    .finding { border-top:1px solid #eeece5; padding:10px 0 }
    .finding:first-of-type { border-top:0 }
    pre { white-space:pre-wrap; word-break:break-all; font-size:11px; background:#f7f6f2; padding:8px; border-radius:3px }
    details summary { cursor:pointer; font-size:12px; color:#6b6455 }
    .banner { border-left:3px solid #b3541e; background:#fff; padding:12px 16px; margin:16px 0 }
    """
    run = panel.get("run") or {}
    parts = [
        "<!doctype html><html lang=en><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        f"<title>Recorded acceptance review - {esc(run.get('run'))}</title><style>{css}</style></head><body>",
        "<h1>Recorded acceptance review</h1>",
        f"<p class=muted>{esc(run.get('run'))} &middot; artifact <code>{esc(run.get('artifact'))}</code>"
        f" &middot; {esc(run.get('verdict'))} &middot; {esc(run.get('recording'))}</p>",
    ]
    if panel.get("declared_gaps"):
        gaps = "".join(f"<li>{esc(gap)}</li>" for gap in panel["declared_gaps"])
        parts.append(f"<div class=banner><strong>Declared gaps in this review</strong><ul>{gaps}</ul></div>")
    parts.append("<h2>Capability matrix</h2>" + render_capabilities(panel.get("capabilities") or []))
    parts.append("<h2>Deterministic analysis (primary detector)</h2>"
                 + render_findings(panel.get("findings") or [], panel_dir))
    cadence = ""
    analysis = panel.get("recording_analysis") or {}
    if analysis.get("frames") and analysis.get("span_ms"):
        cadence = (" The recorder captured %.1f frames per second, which bounds what a clip can "
                   "show; the clip frames are sampled at 10 fps from that source."
                   % (analysis["frames"] / (analysis["span_ms"] / 1000)))
    parts.append("<h2>Flagged clips</h2><p class=muted>Only flagged windows are cut."
                 + cadence + "</p>"
                 + render_clip_reviews(panel.get("clip_reviews") or [], panel_dir))
    parts.append("<h2>Vision checker</h2>" + render_vision_checks(panel.get("vision_checks") or []))
    parts.append("<h2>Six lenses</h2>" + render_lenses(panel.get("lenses") or [], panel_dir))
    parts.append("<p class=muted>Built by apps/macos/FirstLine/scripts/design-panel.sh. The deterministic "
                 "analysis runs on every recording and is the assertion source; the model stages only read "
                 "captures and never decide an action.</p></body></html>")
    output = os.path.join(panel_dir, "report.html")
    with open(output, "w", encoding="utf-8") as handle:
        handle.write("\n".join(parts))
    print(output)


def main():
    if len(sys.argv) < 2:
        print("usage: panel-lib.py extract|report <evidence-dir>", file=sys.stderr)
        return 2
    if sys.argv[1] == "extract":
        return extract()
    if sys.argv[1] == "report":
        return report()
    print(f"unknown command {sys.argv[1]}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
