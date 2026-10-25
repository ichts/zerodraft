#!/usr/bin/env python3
"""Helpers for the design panel and for the acceptance verdict.

[INPUT] `turn` and `verdict` read the JSONL stream `pi --mode json` prints on stdin;
        `verdict` also takes the stage it has to answer (`lens`, `clip` or `vision`)
        and, for a lens, the lens that was asked. `clip` reads the assembled
        recording plus the frame manifest. `status` and `record` read
        <evidence>/panel/stage-*.json, <evidence>/acceptance.txt and the lens names
        their caller requires; `record` also reads <evidence>/journey.log for whether an
        assertion actually failed, writes the derived review lines, `gate` reads only
        the review record, and `command` prints the one pasteable re-run command.
        `report` reads <evidence>/panel/panel.json plus the thumbnails the panel
        script wrote.
[OUTPUT] The terminal state of a model turn, one JSON verdict per model turn (either
         `{"status": "complete", "answer": <validated answer>}` or `{"status":
         "unavailable", "error": "<reason>"}`); a JSON clip record (origin, seek and
         the extracted frame names); the diagnostic summary `status` prints from the
         panel stages and the panel gate `gate` reads from the review record and exits
         with (0 complete, 79 not), so an incomplete review is a failing command rather
         than a number its caller has to compare;
         the pasteable re-run command for a bundle; the derived review lines of
         acceptance.txt, with re-run provenance; or a self-contained static HTML report
         whose images are inlined so the bundle can be read on its own.
[POS] apps/macos/FirstLine/scripts/vm/panel-lib.py - the small, boring part of
      design-panel.sh and vm-journey.sh: model-answer parsing and validation, clip
      cutting, lens summary and report rendering.
[PROTOCOL] The recording's own time origin is the first timestamp in frames.tsv,
           because that frame is time zero of the assembled video. A model turn
           counts only when its last turn_end ended with stopReason stop and its text
           carries a JSON object shaped for that stage; a lens answer counts only when
           the lens it declares is the lens that was asked. Anything else is recorded
           as unavailable with the exact reason. The blocked sign-off reason is the
           observed failure of a requested lens or the required lens that is missing,
           never a fixed probe result. Report rendering never invents content: a stage
           that did not run is rendered as a declared gap with its recorded reason, and
           a lens with no answer is rendered as unavailable rather than omitted. Nothing
           here signs off by default: the sign-off is `accepted` only for the recorded
           `accepted` verdict, and the gate command fails for any record that is not
           complete.
"""

import argparse
import base64
import glob
import html
import json
import math
import os
import re
import shlex
import subprocess
import sys
import time

SEVERITY_ORDER = {"blocker": 0, "major": 1, "minor": 2, "nit": 3, "info": 4}
# A flagged clip covers the window plus this much either side, sampled at this rate
# and never longer than a minute of recording.
CLIP_LEAD_MS = 1000
CLIP_FPS = 10
CLIP_MIN_FRAMES = 6
CLIP_MAX_FRAMES = 60
LENS_VERDICTS = {"sound", "needs work", "blocked"}
CLIP_VERDICTS = {"defect", "expected"}
CLIP_SEVERITIES = {"blocker", "major", "minor", "nit"}
# The lines of acceptance.txt this module owns: it rewrites them from the panel stages
# so the record always describes the review artifact beside it.
DERIVED_RECORD_KEYS = ("analysis:", "panel:", "panel_lenses_complete:", "panel_lenses_required:",
                       "panel_command:", "panel_lens:", "panel_not_run:", "sign_off:",
                       "review:", "review_lenses:")


def first_json_object(text):
    """The first complete JSON object in a model answer, or None."""
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
                    try:
                        return json.loads(candidate[start:index + 1])
                    except json.JSONDecodeError:
                        break
        start = candidate.find("{", start + 1)
    return None


def model_turn(stream):
    """The last turn_end of a `pi --mode json` stream: seen, stopReason, text, error."""
    seen = False
    stop_reason = ""
    error_message = ""
    text = ""
    for line in stream:
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(record, dict):
            continue
        if record.get("type") == "message_end":
            error_message = (record.get("message") or {}).get("errorMessage") or error_message
            continue
        if record.get("type") != "turn_end":
            continue
        seen = True
        message = record.get("message") or {}
        stop_reason = message.get("stopReason") or ""
        chunks = [item["text"] for item in message.get("content") or []
                  if isinstance(item, dict) and item.get("type") == "text" and item.get("text")]
        if chunks:
            text = chunks[-1]
    return seen, stop_reason, text, error_message


def normalised_text(value):
    return value.strip() if isinstance(value, str) else ""


def lens_answer(value, expected):
    declared = normalised_text(value.get("lens"))
    if not declared:
        return None, "the answer names no lens"
    if declared.lower() != expected.lower():
        return None, f"the answer declared lens {declared!r} instead of {expected!r}"
    verdict = normalised_text(value.get("verdict")).lower()
    if verdict not in LENS_VERDICTS:
        return None, f"the answer has no lens verdict (got {value.get('verdict')!r})"
    if not isinstance(value.get("findings"), list):
        return None, "the answer has no findings list"
    return {"lens": expected, "verdict": verdict,
            "summary": normalised_text(value.get("summary")),
            "findings": [item for item in value["findings"] if isinstance(item, dict)]}, ""


def clip_answer(value, _expected):
    verdict = normalised_text(value.get("verdict")).lower()
    if verdict not in CLIP_VERDICTS:
        return None, f"the answer has no clip verdict (got {value.get('verdict')!r})"
    severity = normalised_text(value.get("severity")).lower()
    if severity not in CLIP_SEVERITIES:
        return None, f"the answer has no severity (got {value.get('severity')!r})"
    reason = normalised_text(value.get("reason"))
    if not reason:
        return None, "the answer gives no reason"
    return {"verdict": verdict, "severity": severity, "reason": reason,
            "what_to_fix": normalised_text(value.get("what_to_fix"))}, ""


def vision_answer(value, _expected):
    valid = value.get("next_step_valid")
    if not isinstance(valid, bool):
        return None, "the answer does not say whether the next step is valid"
    index = value.get("check_step_index")
    if not isinstance(index, int) or isinstance(index, bool):
        return None, "the answer has no numeric check_step_index"
    reason = normalised_text(value.get("reason"))
    if not reason:
        return None, "the answer gives no reason"
    return {"next_step_valid": valid, "check_step_index": index, "reason": reason}, ""


ANSWERS = {"lens": lens_answer, "clip": clip_answer, "vision": vision_answer}


def turn():
    """The terminal state of a `pi --mode json` stream: `stop` when it answered, else why."""
    seen, stop_reason, _text, error_message = model_turn(sys.stdin)
    if error_message:
        print(error_message)
        return 1
    if not seen:
        print("the model stream has no turn_end record")
        return 1
    if stop_reason != "stop":
        print(f"the model turn ended with stopReason {stop_reason or 'unknown'}")
        return 1
    print("stop")
    return 0


def verdict(argv):
    """Validate one model turn against the stage it was asked to answer."""
    stage = argv[0] if argv else ""
    expected = argv[1] if len(argv) > 1 else ""
    if stage not in ANSWERS:
        print(f"panel-lib: unknown answer stage {stage!r}", file=sys.stderr)
        return 2
    if stage == "lens" and not expected:
        print("panel-lib: verdict lens needs the lens that was asked", file=sys.stderr)
        return 2
    seen, stop_reason, text, error_message = model_turn(sys.stdin)

    def unavailable(reason):
        print(json.dumps({"status": "unavailable", "error": error_message or reason},
                         sort_keys=True))
        return 0

    if not seen:
        return unavailable("the model stream has no turn_end record")
    if stop_reason != "stop":
        return unavailable(f"the model turn ended with stopReason {stop_reason or 'unknown'}")
    answer_object = first_json_object(text)
    if not isinstance(answer_object, dict):
        return unavailable("the answer contains no JSON object")
    normalised, problem = ANSWERS[stage](answer_object, expected)
    if problem:
        return unavailable(problem)
    print(json.dumps({"status": "complete", "answer": normalised}, sort_keys=True))
    return 0


def recording_origin_ms(manifest):
    with open(manifest, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            return int(line.split("\t", 1)[0])
    raise SystemExit(f"panel-lib: {manifest} has no captured frame to take the origin from")


def clip(argv):
    parser = argparse.ArgumentParser(prog="panel-lib.py clip")
    parser.add_argument("--video", required=True)
    parser.add_argument("--frames", required=True)
    parser.add_argument("--t-start", type=int, required=True)
    parser.add_argument("--t-end", type=int, required=True)
    parser.add_argument("--out", required=True)
    options = parser.parse_args(argv)
    origin = recording_origin_ms(options.frames)
    seek = max(0.0, (options.t_start - origin) / 1000.0 - CLIP_LEAD_MS / 1000.0)
    span = max(0, options.t_end - options.t_start)
    count = math.ceil((span + 2 * CLIP_LEAD_MS) / 1000.0 * CLIP_FPS)
    count = max(CLIP_MIN_FRAMES, min(CLIP_MAX_FRAMES, count))
    os.makedirs(options.out, exist_ok=True)
    for stale in glob.glob(os.path.join(options.out, "clip-*.png")):
        os.remove(stale)
    pattern = os.path.join(options.out, "clip-%03d.png")
    command = ["ffmpeg", "-loglevel", "error", "-nostdin", "-ss", "%.3f" % seek,
               "-i", options.video, "-vf", "fps=%d" % CLIP_FPS, "-frames:v", str(count),
               pattern, "-y"]
    result = subprocess.run(command, capture_output=True)
    if result.returncode != 0:
        print(f"panel-lib: ffmpeg could not cut the clip: {result.stderr[:400]!r}", file=sys.stderr)
        return 1
    frames = sorted(os.path.basename(path) for path in glob.glob(os.path.join(options.out, "clip-*.png")))
    print(json.dumps({"origin_ms": origin, "seek_s": round(seek, 3),
                      "window_ms": [options.t_start, options.t_end], "frames": frames},
                     sort_keys=True))
    return 0


def panel_state(evidence, required=None):
    """The one derivation of what the review artifact holds."""
    panel_dir = os.path.join(os.path.abspath(evidence), "panel")
    lenses = []
    lens_stage = os.path.join(panel_dir, "stage-04-lenses.json")
    if os.path.exists(lens_stage):
        with open(lens_stage, encoding="utf-8") as handle:
            lenses = json.load(handle).get("lenses") or []
    analysis = {}
    capability_stage = os.path.join(panel_dir, "stage-05-capabilities.json")
    if os.path.exists(capability_stage):
        with open(capability_stage, encoding="utf-8") as handle:
            analysis = next((capability for capability in json.load(handle).get("capabilities") or []
                             if capability.get("stage") == "deterministic analysis"), {})
    if required is None:
        required = [lens.get("lens") for lens in lenses if lens.get("lens")]
    complete = [lens for lens in lenses if lens.get("status") == "complete"]
    incomplete = [lens for lens in lenses if lens.get("status") != "complete"]
    complete_names = {lens.get("lens") for lens in complete}
    missing = [name for name in required if name not in complete_names]
    blocked = len(complete) < len(lenses) or bool(missing)
    reason = ""
    if incomplete:
        reason = " ".join(str(incomplete[0].get("error") or "").split())
        if not reason:
            reason = "the panel recorded no answer for %s" % (incomplete[0].get("lens") or "?")
    if not reason and missing:
        reason = "the panel recorded no result for %s" % " ".join(missing)
    if blocked:
        reason = " ".join(str(reason or "the panel recorded no lens result").split())
    if analysis:
        analysis_line = " ".join(("%s (%s)" % (
            analysis.get("status") or "not recorded",
            analysis.get("detail") or "")).split())
    else:
        analysis_line = "not recorded: the panel wrote no deterministic analysis status"
    return {"lenses": lenses, "required": list(required), "missing": missing,
            "complete_count": len(complete), "total": len(lenses), "blocked": blocked,
            "reason": reason, "analysis": analysis_line}


def lens_status(evidence, required):
    """Shell-readable summary of the panel stages the host verdict reads."""
    state = panel_state(evidence, required)
    print("analysis=%s" % state["analysis"])
    print("lenses_total=%d" % state["total"])
    print("lenses_complete=%d" % state["complete_count"])
    if required:
        print("lenses_required_missing=%s" % " ".join(state["missing"]))
    for lens in state["lenses"]:
        answer_object = lens.get("answer") or {}
        print("lens=%s\t%s\t%s\t%d\t%s" % (
            lens.get("lens") or "?", lens.get("status") or "unavailable",
            answer_object.get("verdict") or "-", len(answer_object.get("findings") or []),
            " ".join((lens.get("error") or "").split())))
    if state["blocked"]:
        print("reason=%s" % state["reason"])
    return 0


def sign_off_text(verdict, state, record, failed_assertion):
    if verdict == "rejected":
        if record.get("declared_known_defect_state") == "did-not-reproduce":
            return "not accepted - the declared known defect did not reproduce on this run"
        if failed_assertion:
            return "not accepted - an assertion or the recording failed"
        return "not accepted - the run was rejected without a failed assertion"
    if state["blocked"]:
        return "blocked - the six-lens review did not run (%s)" % state["reason"]
    if verdict == "accepted-with-declared-defect":
        return "not accepted - the declared known defect reproduced on this artifact"
    if verdict != "accepted":
        return "not accepted - the record states no accepted verdict (%s)" % (verdict or "none")
    return "accepted"


def panel_command_text(evidence):
    """The one pasteable re-run command for a bundle."""
    design_panel = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                "design-panel.sh")
    return "bash %s %s" % (shlex.quote(design_panel), shlex.quote(os.path.abspath(evidence)))


def panel_gate(evidence):
    """The panel gate's exit code, read only from the review record."""
    acceptance = os.path.join(os.path.abspath(evidence), "acceptance.txt")
    state = ""
    if os.path.exists(acceptance):
        with open(acceptance, encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("panel: "):
                    state = line.split(":", 1)[1].strip()
    return 0 if state == "complete" else 79


def review_record(argv):
    """Rewrite the derived review lines in acceptance.txt from the panel stages."""
    parser = argparse.ArgumentParser(prog="panel-lib.py record")
    parser.add_argument("evidence")
    parser.add_argument("--require", nargs="*", default=[])
    options = parser.parse_args(argv)
    evidence = os.path.abspath(options.evidence)
    acceptance = os.path.join(evidence, "acceptance.txt")
    if not os.path.exists(acceptance):
        print(f"panel-lib: {acceptance} does not exist", file=sys.stderr)
        return 1
    with open(acceptance, encoding="utf-8") as handle:
        lines = [line for line in handle.read().split("\n") if line]
    base = [line for line in lines if not line.startswith(DERIVED_RECORD_KEYS)]
    previous = any(line.startswith(("panel:", "sign_off:")) for line in lines)
    record = {}
    for line in lines:
        key, _, value = line.partition(":")
        record.setdefault(key.strip(), value.strip())
    verdict = record.get("verdict", "")
    journey = os.path.join(evidence, "journey.log")
    failed_assertion = False
    if os.path.exists(journey):
        with open(journey, encoding="utf-8", errors="replace") as handle:
            failed_assertion = any(line.startswith("FAIL ") for line in handle)
    required = list(options.require)
    if not required:
        required = next((line.split(":", 1)[1].split() for line in lines
                         if line.startswith("panel_lenses_required:")), [])
    state = panel_state(evidence, required or None)
    panel_line = "complete" if not state["blocked"] else "not run"
    derived = [
        "analysis: %s" % state["analysis"],
        "panel: %s" % panel_line,
        "panel_lenses_complete: %d/%d" % (state["complete_count"], state["total"]),
        "panel_lenses_required: %s" % " ".join(state["required"]),
        "panel_command: %s" % panel_command_text(evidence),
    ]
    derived.extend("panel_lens: %s\t%s\t%s\t%d" % (
        lens.get("lens") or "?", lens.get("status") or "unavailable",
        (lens.get("answer") or {}).get("verdict") or "-",
        len((lens.get("answer") or {}).get("findings") or [])) for lens in state["lenses"])
    if state["blocked"]:
        derived.append("panel_not_run: %s" % state["reason"])
    derived.append("sign_off: %s" % sign_off_text(verdict, state, record, failed_assertion))
    timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    lens_results = " ".join("%s=%s:%s" % (
        lens.get("lens") or "?", lens.get("status") or "unavailable",
        (lens.get("answer") or {}).get("verdict") or "-") for lens in state["lenses"])
    if previous:
        derived.append("review: updated by a design-panel re-run at %s; this repairs the review "
                       "artifact only and does not re-validate the product" % timestamp)
        derived.append("review_lenses: %s" % lens_results)
    temporary = acceptance + ".writing"
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write("\n".join(base + derived) + "\n")
    os.replace(temporary, acceptance)
    if previous:
        with open(os.path.join(evidence, "notes.md"), "a", encoding="utf-8") as handle:
            handle.write("\n## Review record updated after the run\n\n")
            handle.write("- %s design-panel re-run: panel %s, %d of %d lenses complete.\n" % (
                timestamp, panel_line, state["complete_count"], state["total"]))
            handle.write("- Lens results: %s\n" % lens_results)
            handle.write("- This repairs the review artifact only; the run verdict is unchanged.\n")
    print("review record written to %s" % acceptance)
    return 0


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


def seconds_from_origin(origin, moment):
    """A wall-clock stamp as seconds from the recording's first captured frame."""
    if origin is None or moment in (None, ""):
        return None
    try:
        return (int(moment) - origin) / 1000
    except (TypeError, ValueError):
        return None


def window_text(origin, finding):
    """The flagged window in recording time, which is what a reviewer can seek to."""
    start = seconds_from_origin(origin, finding.get("t_start"))
    if start is None:
        return ""
    end = seconds_from_origin(origin, finding.get("t_end"))
    if end is None:
        return "%+.2f s" % start
    return "%+.2f s &rarr; %+.2f s" % (start, end)


def render_findings(findings, panel_dir, origin=None):
    if not findings:
        return "<p class=muted>No deterministic findings were recorded for this run.</p>"
    rows = []
    ordered = sorted(findings, key=lambda f: (SEVERITY_ORDER.get((f.get("severity") or "").lower(), 9),
                                              f.get("t_start") or 0))
    for finding in ordered:
        window = window_text(origin, finding)
        thumbs = "".join(image(panel_dir, f'frame-{finding["t_start"]}-{index}.jpg')
                         for index in range(6))
        rows.append(f"""<tr><td>{severity_badge(finding.get('severity'))}</td>
<td><code>{esc(finding.get('kind'))}</code><br><code>{esc(finding.get('assertion') or 'informational')}</code></td>
<td>{esc(finding.get('note'))}<br><span class=muted>{window} &middot; {esc(finding.get('duration_ms'))} ms</span></td>
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


def evidence_thumb(panel_dir, reference):
    """The thumbnail design-panel.sh wrote for a lens's evidence capture."""
    if not reference:
        return ""
    return image(panel_dir, os.path.splitext(os.path.basename(reference))[0] + ".jpg")


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
            thumb = evidence_thumb(panel_dir, reference)
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
    analysis = panel.get("recording_analysis") or {}
    manifest = os.path.join(evidence, "frames.tsv")
    origin = recording_origin_ms(manifest) if os.path.exists(manifest) else None
    analysis_sections = []
    if analysis.get("error"):
        analysis_sections.append(
            "<div class=banner><strong>The deterministic analysis did not complete.</strong>"
            f"<p>{esc(analysis['error'])}</p></div>")
    analysis_sections.append(render_findings(panel.get("findings") or [], panel_dir, origin))
    parts.append("<h2>Deterministic analysis (primary detector)</h2>" + "".join(analysis_sections))
    cadence = ""
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
        print("usage: panel-lib.py turn|verdict|clip|status|record|command|gate|report", file=sys.stderr)
        return 2
    command = sys.argv[1]
    if command == "turn":
        return turn()
    if command == "verdict":
        return verdict(sys.argv[2:])
    if command == "clip":
        return clip(sys.argv[2:])
    if command == "status":
        arguments = sys.argv[2:]
        if not arguments:
            print("usage: panel-lib.py status <evidence-dir> [--require <lens> ...]", file=sys.stderr)
            return 2
        rest = arguments[1:]
        if rest and rest[0] != "--require":
            print(f"panel-lib: unknown status option {rest[0]!r}", file=sys.stderr)
            return 2
        return lens_status(arguments[0], rest[1:])
    if command == "record":
        return review_record(sys.argv[2:])
    if command == "command":
        if len(sys.argv) < 3:
            print("usage: panel-lib.py command <evidence-dir>", file=sys.stderr)
            return 2
        print(panel_command_text(sys.argv[2]))
        return 0
    if command == "gate":
        if len(sys.argv) < 3:
            print("usage: panel-lib.py gate <evidence-dir>", file=sys.stderr)
            return 2
        code = panel_gate(sys.argv[2])
        print(code)
        return code
    if command == "report":
        return report()
    print(f"unknown command {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
