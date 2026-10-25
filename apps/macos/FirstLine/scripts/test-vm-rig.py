#!/usr/bin/env python3
"""Executable checks for the recorded-acceptance rig's shared boundaries.

[INPUT] None. Requires ffmpeg, python3 and (for one known-broken probe) jq, which the
        rig itself requires.
[OUTPUT] One PASS/FAIL line per check on stdout; exit 0 only when every check passes.
[POS] apps/macos/FirstLine/scripts/test-vm-rig.py - drives the pieces the VM journey
      and the design panel share: the panel answer validation, the recording-relative
      clip seek, the analyser's frame alignment, the lens summary the host verdict
      reads, guest setup's launchd shim, and the tracked-file guard.
[PROTOCOL] Every check runs the real executable or git on a fixture and asserts its
           observable output; nothing here greps the scripts' source. The known-broken
           cases feed the previous behaviour (a manifest whose first stamp is the
           pre-recording span, a dropped capture, an all-static frame stream with a step
           stamped inside it, the old jq content filter, one review repeated for every
           lens, a bytecode cache tracked in any subtree, a host entry point without its
           launchd shim) and must fail, so a regression reopens the finding. The bytecode guard resolves the repository root and constructs
           its failure case in a scratch repository, and both host entry points are
           checked in a layout that has and lacks the shim.
"""

import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PANEL_LIB = os.path.join(HERE, "vm", "panel-lib.py")
ANALYSER = os.path.join(HERE, "vm", "analyse-recording.py")
DESIGN_PANEL = os.path.join(HERE, "design-panel.sh")
WIDRIG = os.path.join(HERE, "vm", "widrig.swift")
PREPARE_GUEST = os.path.join(HERE, "vm", "prepare-guest.sh")
VM_JOURNEY = os.path.join(HERE, "vm-journey.sh")
# The acceptance contract's lens set, as vm-journey.sh states it.
REQUIRED_LENSES = ["rams", "norman", "spiekermann", "kare", "matas", "vignelli"]

# Twelve solid colours with enough separation to tell neighbouring seconds apart after
# JPEG compression and an H.264 round trip.
PALETTE = ["000000", "ffffff", "cc2214", "1f8f3c", "2b46c8", "e0c020",
           "b02f9a", "159fa8", "e07a1e", "6b2fa0", "808080", "144d28"]
BYTECODE_SUFFIXES = (".pyc", ".pyo")


def tracked_bytecode(paths):
    """Tracked paths that are interpreter build artifacts, not sources."""
    return [path for path in paths
            if "__pycache__/" in path or path.endswith(BYTECODE_SUFFIXES)]


def need(condition, message):
    if not condition:
        raise AssertionError(message)


def run(command, stdin=None, timeout=120):
    return subprocess.run(command, input=stdin, capture_output=True, text=True,
                          timeout=timeout)


def average_colour(path):
    result = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-nostdin", "-i", path,
         "-vf", "scale=1:1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True)
    need(result.returncode == 0 and len(result.stdout) == 3,
         f"could not read the colour of {os.path.basename(path)}")
    return tuple(result.stdout[:3])


def palette_index(colour):
    def distance(entry):
        expected = tuple(int(entry[index:index + 2], 16) for index in (0, 2, 4))
        return sum(abs(left - right) for left, right in zip(expected, colour))
    return min(range(len(PALETTE)), key=lambda index: distance(PALETTE[index]))


def solid_png(path, colour, width=96, height=54):
    result = run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi",
                  "-i", f"color=c=0x{colour}:s={width}x{height}:d=1",
                  "-frames:v", "1", path])
    need(result.returncode == 0, f"could not write {path}: {result.stderr[:200]}")


def build_seconds_video(workdir):
    """A video whose second N is PALETTE[N], as 10 fps frames."""
    seconds = os.path.join(workdir, "seconds")
    os.makedirs(seconds)
    for index, colour in enumerate(PALETTE):
        solid_png(os.path.join(seconds, f"sec-{index:02d}.png"), colour)
    video = os.path.join(workdir, "screen.mov")
    result = run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "1",
                  "-i", os.path.join(seconds, "sec-%02d.png"),
                  "-vf", "fps=10", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                  "-r", "10", video])
    need(result.returncode == 0, f"could not build the fixture video: {result.stderr[:300]}")
    return video


def write_manifest(path, origin_ms, frames=48):
    with open(path, "w", encoding="utf-8") as handle:
        for index in range(frames):
            handle.write("%d\t%06d.jpg\n" % (origin_ms + index * 250, index))


def write_answer_stream(path, text, stop_reason="stop"):
    records = [
        {"type": "message_start"},
        {"type": "turn_end", "message": {"stopReason": "tool_use", "content": [
            {"type": "tool_result", "toolCallId": "1", "output": "no answer yet"}]}},
        {"type": "message_end", "message": {"errorMessage": ""}},
        {"type": "turn_end", "message": {"stopReason": stop_reason, "content": [
            {"type": "thinking", "text": ""},
            {"type": "text", "text": text}]}},
    ]
    with open(path, "w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record) + "\n")


def model_verdict(stream, stage, expected=None):
    command = [sys.executable, PANEL_LIB, "verdict", stage]
    if expected is not None:
        command.append(expected)
    with open(stream, encoding="utf-8") as handle:
        result = run(command, stdin=handle.read())
    need(result.returncode == 0, f"verdict {stage} failed: {result.stderr[:200]}")
    return json.loads(result.stdout)


def check_answer_validation(workdir):
    stream = os.path.join(workdir, "lens.jsonl")
    payload = {"lens": "rams", "verdict": "sound", "summary": "quiet and ordered",
               "findings": []}
    write_answer_stream(stream, json.dumps(payload))
    accepted = model_verdict(stream, "lens", "rams")
    need(accepted["status"] == "complete",
         f"a well-formed lens review was rejected: {accepted}")
    need(accepted["answer"]["lens"] == "rams" and accepted["answer"]["verdict"] == "sound",
         f"the validated answer lost its fields: {accepted['answer']}")

    # The lens that answered must be the lens that was asked, whatever the casing.
    capitalised = os.path.join(workdir, "capitalised.jsonl")
    write_answer_stream(capitalised, json.dumps(dict(payload, lens="Rams")))
    need(model_verdict(capitalised, "lens", "rams")["status"] == "complete",
         "a lens answer with different casing was rejected")
    mismatched = os.path.join(workdir, "mismatched.jsonl")
    write_answer_stream(mismatched, json.dumps(dict(payload, lens="norman")))
    wrong = model_verdict(mismatched, "lens", "rams")
    need(wrong["status"] == "unavailable",
         f"an answer for another lens counted as this lens: {wrong}")
    need("norman" in wrong["error"] and "rams" in wrong["error"],
         f"the rejection does not name both lenses: {wrong['error']!r}")

    # Any JSON object used to count as a completed lens. It must not: this is not a
    # lens review, and a lens may only count once it answered as a lens.
    not_a_review = os.path.join(workdir, "not-a-review.jsonl")
    write_answer_stream(not_a_review, json.dumps({"error": "cannot read images"}))
    rejected = model_verdict(not_a_review, "lens", "rams")
    need(rejected["status"] == "unavailable",
         f"a non-lens JSON object counted as a reviewed lens: {rejected}")
    need("lens" in rejected["error"],
         f"the rejection does not name the missing field: {rejected['error']!r}")

    # A turn that ended abnormally is not an answer even when its JSON parses.
    truncated = os.path.join(workdir, "truncated.jsonl")
    write_answer_stream(truncated, json.dumps(payload), stop_reason="length")
    cut = model_verdict(truncated, "lens", "rams")
    need(cut["status"] == "unavailable" and "length" in cut["error"],
         f"a truncated turn counted as a lens review: {cut}")

    clip_stream = os.path.join(workdir, "clip.jsonl")
    write_answer_stream(clip_stream, json.dumps({
        "verdict": "expected", "severity": "minor", "reason": "the scripted step landed"}))
    need(model_verdict(clip_stream, "clip")["status"] == "complete",
         "a well-formed clip verdict was rejected")
    bad_clip = os.path.join(workdir, "bad-clip.jsonl")
    write_answer_stream(bad_clip, json.dumps({"verdict": "maybe", "severity": "minor",
                                              "reason": "unclear"}))
    need(model_verdict(bad_clip, "clip")["status"] == "unavailable",
         "a clip answer with no clip verdict counted as reviewed")

    vision_stream = os.path.join(workdir, "vision.jsonl")
    write_answer_stream(vision_stream, json.dumps({
        "next_step_valid": True, "check_step_index": 3, "reason": "the next step still fits"}))
    need(model_verdict(vision_stream, "vision")["status"] == "complete",
         "a well-formed vision check was rejected")
    bad_vision = os.path.join(workdir, "bad-vision.jsonl")
    write_answer_stream(bad_vision, json.dumps({
        "next_step_valid": True, "check_step_index": "3", "reason": "the next step still fits"}))
    need(model_verdict(bad_vision, "vision")["status"] == "unavailable",
         "a vision check with a textual step index counted as reviewed")

    if shutil.which("jq") is not None:
        legacy = run(["jq", "-r",
                      'select(.type=="turn_end") | .message.content[]? | select(type=="text") | .text'],
                     stdin=open(stream, encoding="utf-8").read())
        need(legacy.returncode == 0 and legacy.stdout.strip() == "",
             "the previous filter was proven broken by returning no text; it returned one")


def check_clip_origin(workdir):
    video = build_seconds_video(workdir)
    origin = 1_700_000_000_000
    true_manifest = os.path.join(workdir, "frames.tsv")
    write_manifest(true_manifest, origin)
    flag_start = origin + 8400
    flag_end = flag_start + 300
    out = os.path.join(workdir, "clip-true")
    result = run([sys.executable, PANEL_LIB, "clip", "--video", video,
                  "--frames", true_manifest, "--t-start", str(flag_start),
                  "--t-end", str(flag_end), "--out", out])
    need(result.returncode == 0, f"clip failed: {result.stderr[:300]}")
    described = json.loads(result.stdout)
    need(described["origin_ms"] == origin,
         f"the clip used origin {described['origin_ms']} instead of the first captured frame")
    need(described["frames"], "the clip extracted no frames for a flagged window")
    first = palette_index(average_colour(os.path.join(out, described["frames"][0])))
    need(first == 7,
         f"the clip started on second {first} instead of the second before the flag")
    seen = {palette_index(average_colour(os.path.join(out, name)))
            for name in described["frames"]}
    need(8 in seen, f"the flagged second is missing from the clip (saw seconds {sorted(seen)})")

    # Known-broken: the previous code seeked from the guest's pre-recording span, which
    # starts before the recorder's first frame. That origin must miss the flag.
    legacy_manifest = os.path.join(workdir, "pre-recording-origin.tsv")
    write_manifest(legacy_manifest, origin - 6000)
    legacy_out = os.path.join(workdir, "clip-legacy")
    legacy = run([sys.executable, PANEL_LIB, "clip", "--video", video,
                  "--frames", legacy_manifest, "--t-start", str(flag_start),
                  "--t-end", str(flag_end), "--out", legacy_out])
    legacy_frames = json.loads(legacy.stdout)["frames"] if legacy.returncode == 0 else []
    legacy_seen = {palette_index(average_colour(os.path.join(legacy_out, name)))
                   for name in legacy_frames}
    need(8 not in legacy_seen,
         "the pre-recording origin still lands on the flagged second, so this "
         "check cannot prove the fix")


def check_analyser_alignment(workdir):
    evidence = os.path.join(workdir, "analysis")
    frames_dir = os.path.join(evidence, "frames")
    os.makedirs(frames_dir)
    for index in range(6):
        solid_png(os.path.join(frames_dir, "%06d.jpg" % index), PALETTE[index],
                  width=192, height=108)
    with open(os.path.join(evidence, "frames.tsv"), "w", encoding="utf-8") as handle:
        for index in range(6):
            handle.write("%d\t%06d.jpg\n" % (1_700_000_000_000 + index * 250, index))
    healthy = run([sys.executable, ANALYSER, evidence])
    need(healthy.returncode == 0,
         f"the analyser failed on an intact frame stream: {healthy.stdout[-400:]}")
    need("PASS [recording-analysis]" in healthy.stdout,
         "the analyser did not record its assertion on an intact frame stream")

    # Known-broken: a capture the recorder failed to write. The manifest still lists it,
    # so the decoded image count no longer matches and the metric would be misaligned.
    os.remove(os.path.join(frames_dir, "000003.jpg"))
    dropped = run([sys.executable, ANALYSER, evidence])
    need(dropped.returncode != 0, "a dropped capture was accepted as a healthy recording")
    need("FAIL [recording-analysis]" in dropped.stdout,
         "a dropped capture produced no failed assertion line")

    # A stream with fewer than two frames cannot be compared; it must record an
    # explicit failure instead of breaking the two-value contract.
    single = os.path.join(workdir, "single-frame")
    os.makedirs(os.path.join(single, "frames"))
    solid_png(os.path.join(single, "frames", "000000.jpg"), PALETTE[0], width=192, height=108)
    with open(os.path.join(single, "frames.tsv"), "w", encoding="utf-8") as handle:
        handle.write("1700000000000\t000000.jpg\n")
    lonely = run([sys.executable, ANALYSER, single])
    need(lonely.returncode != 0, "a single-frame stream was accepted as a recording")
    need("FAIL [recording-analysis]" in lonely.stdout,
         f"a single-frame stream produced no failed assertion: {lonely.stdout[-400:]}")
    need("at least two" in lonely.stdout,
         f"the single-frame failure does not say why: {lonely.stdout[-400:]}")
    with open(os.path.join(single, "findings.json"), encoding="utf-8") as handle:
        recorded = json.load(handle)["recording"]
    need("at least two" in (recorded.get("error") or ""),
         f"the bundle did not record why the analysis failed: {recorded!r}")


def status_fields(evidence, required=REQUIRED_LENSES):
    result = run([sys.executable, PANEL_LIB, "status", evidence, "--require", *required])
    need(result.returncode == 0, f"status failed: {result.stderr[:200]}")
    return result, dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)


def write_lenses(panel, lenses):
    with open(os.path.join(panel, "stage-04-lenses.json"), "w", encoding="utf-8") as handle:
        json.dump({"lenses": lenses}, handle)


def complete_lens(name, verdict="needs work"):
    return {"lens": name, "status": "complete", "model": "fixture",
            "answer": {"lens": name, "verdict": verdict, "findings": []}}


def write_pi_stub(path, body):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("#!/usr/bin/env python3\nimport json, re, sys\nprompt = sys.argv[-1]\n")
        handle.write(body)
        handle.write("print(json.dumps({'type': 'turn_end', 'message': {'stopReason': 'stop',"
                     " 'content': [{'type': 'text', 'text': json.dumps(answer)}]}}))\n")
    os.chmod(path, 0o755)


def check_lens_status(workdir):
    evidence = os.path.join(workdir, "panel-evidence")
    panel = os.path.join(evidence, "panel")
    os.makedirs(panel)
    required = REQUIRED_LENSES
    with open(os.path.join(panel, "stage-05-capabilities.json"), "w", encoding="utf-8") as handle:
        json.dump({"capabilities": [{"stage": "deterministic analysis", "status": "complete",
                                     "detail": "3 finding(s) from scripts/vm/analyse-recording.py, no model"}],
                   "declared_gaps": [
                       "Gemini route cursor/gemini-4-argon is unavailable on this machine: no answer."]}, handle)

    # One lens failed while the others answered: that failure is the reason, not the
    # routine route gap that sits in the same bundle.
    write_lenses(panel, [
        complete_lens("rams", "sound"),
        {"lens": "norman", "status": "unavailable", "error": "the answer names no lens"},
    ])
    result, fields = status_fields(evidence)
    need(fields.get("analysis") ==
         "complete (3 finding(s) from scripts/vm/analyse-recording.py, no model)",
         f"the analysis outcome is not in the host summary: {fields.get('analysis')!r}")
    need(fields.get("lenses_total") == "2", f"wrong total: {fields.get('lenses_total')!r}")
    need(fields.get("lenses_complete") == "1", f"wrong completed count: {fields.get('lenses_complete')!r}")
    need(fields.get("lenses_required_missing") == "norman spiekermann kare matas vignelli",
         f"the required set is not checked by name: {fields.get('lenses_required_missing')!r}")
    need(fields.get("reason") == "the answer names no lens",
         f"the blocked reason is not the observed lens failure: {fields.get('reason')!r}")
    need("Gemini" not in fields.get("reason", ""),
         f"the blocking reason named an unrelated capability gap: {fields.get('reason')!r}")
    rams = [line for line in result.stdout.splitlines() if line.startswith("lens=rams")]
    need(rams and rams[0].split("\t")[1:] == ["complete", "sound", "0", ""],
         f"the rams lens line is wrong: {rams!r}")

    # No lens could run at all: the recorded no-model reason wins over the route gap.
    write_lenses(panel, [{"lens": name, "status": "unavailable",
                          "error": "no reviewer model answered"} for name in required])
    _, fields = status_fields(evidence)
    need(fields.get("reason") == "no reviewer model answered",
         f"the no-lens reason is not the actual cause: {fields.get('reason')!r}")

    # A lens failed without an error of its own: its name is the reason, not the gap
    # and not the missing-required-name sentence.
    write_lenses(panel, [complete_lens(name) for name in required]
                 + [{"lens": "extra", "status": "unavailable"}])
    _, fields = status_fields(evidence)
    need(fields.get("reason") == "the panel recorded no answer for extra",
         f"an errored-out lens was masked: {fields.get('reason')!r}")

    # All recorded lenses answered, but the required name is absent (a renamed list).
    # The missing name is the reason; the route gap must not stand in for it.
    write_lenses(panel, [complete_lens(name) for name in required[:-1]])
    _, fields = status_fields(evidence)
    need(fields.get("lenses_required_missing") == required[-1],
         f"the missing required name is wrong: {fields.get('lenses_required_missing')!r}")
    need(fields.get("reason") == "the panel recorded no result for %s" % required[-1],
         f"the missing required name was masked by a gap: {fields.get('reason')!r}")

    write_lenses(panel, [complete_lens(name) for name in required])
    result, fields = status_fields(evidence)
    need(fields.get("lenses_required_missing") == "",
         f"a complete required set reported missing lenses: {fields.get('lenses_required_missing')!r}")
    need("reason=" not in result.stdout,
         "a complete lens stage still reported a blocking reason")


def write_launch_stream(path, declared_text="Activate Write It Down"):
    records = [
        {"t": 1000.0, "text": declared_text},
        {"t": 1000.6, "text": "Begin writing"},
        {"t": 1001.2, "text": "Begin writing"},
    ]
    with open(path, "w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record) + "\n")


def check_launch_assertion_ids(workdir):
    evidence = os.path.join(workdir, "launch")
    frames_dir = os.path.join(evidence, "frames")
    os.makedirs(frames_dir)
    for index in range(3):
        solid_png(os.path.join(frames_dir, "%06d.jpg" % index), PALETTE[index],
                  width=192, height=108)
    with open(os.path.join(evidence, "frames.tsv"), "w", encoding="utf-8") as handle:
        for index in range(3):
            handle.write("%d\t%06d.jpg\n" % (1_700_000_000_000 + index * 250, index))

    trial = os.path.join(evidence, "launch-trial.jsonl")
    write_launch_stream(trial)
    trial_run = run([sys.executable, ANALYSER, evidence])
    need(trial_run.returncode != 0, "a transient activation page in the trial launch passed")
    need("FAIL [launch-trial-no-activation-page]" in trial_run.stdout,
         f"the trial launch did not fail under its own assertion id: {trial_run.stdout[-400:]}")
    need("FAIL [licensed-launch-no-activation-page]" not in trial_run.stdout,
         "the trial launch borrowed the declared-defect assertion id")

    os.remove(trial)
    write_launch_stream(os.path.join(evidence, "launch-licensed-1.jsonl"))
    licensed_run = run([sys.executable, ANALYSER, evidence])
    need(licensed_run.returncode != 0, "a transient activation page in a licensed relaunch passed")
    need("FAIL [licensed-launch-no-activation-page]" in licensed_run.stdout,
         f"the licensed relaunch lost its declared-defect assertion id: {licensed_run.stdout[-400:]}")


def write_frame_stream(evidence, colours, origin_ms=1_700_000_000_000, tick_ms=250):
    """A frame stream whose frame N is colours[N], one frame every tick."""
    frames_dir = os.path.join(evidence, "frames")
    os.makedirs(frames_dir)
    for index, colour in enumerate(colours):
        solid_png(os.path.join(frames_dir, "%06d.jpg" % index), colour, width=192, height=108)
    with open(os.path.join(evidence, "frames.tsv"), "w", encoding="utf-8") as handle:
        for index in range(len(colours)):
            handle.write("%d\t%06d.jpg\n" % (origin_ms + index * tick_ms, index))
    return origin_ms


def stamp_step(evidence, origin_ms, offset_ms, name):
    moment = datetime.datetime.fromtimestamp((origin_ms + offset_ms) / 1000,
                                             datetime.timezone.utc)
    with open(os.path.join(evidence, "steps.tsv"), "a", encoding="utf-8") as handle:
        handle.write(moment.strftime("%Y-%m-%dT%H:%M:%SZ") + "\t" + name + "\n")


def check_frozen_recording(workdir):
    # Known-broken: every frame of the run is the same image, and the guest stamped
    # steps on its own clock inside that still window. A step stamp cannot make a dead
    # capture evidence of a working app, so the run must fail.
    stalled = os.path.join(workdir, "stalled")
    origin = write_frame_stream(stalled, [PALETTE[4]] * 96)
    for index in range(4):
        stamp_step(stalled, origin, 5000 + index * 5000, "%02d-step" % index)
    stalled_run = run([sys.executable, ANALYSER, stalled])
    need(stalled_run.returncode != 0,
         f"a recording whose screen never changes was accepted: {stalled_run.stdout[-400:]}")
    need("FAIL [recording-stall]" in stalled_run.stdout,
         f"the stalled recording produced no recording-stall failure: {stalled_run.stdout[-400:]}")

    # The excuse that survives: a still desktop while a command-line step runs, in a
    # recording that does show the screen changing around it.
    quiet = os.path.join(workdir, "quiet-step")
    origin = write_frame_stream(quiet, PALETTE[:8] + [PALETTE[9]] * 96)
    stamp_step(quiet, origin, 8000, "08-command-line-step")
    quiet_run = run([sys.executable, ANALYSER, quiet])
    need(quiet_run.returncode == 0,
         f"a still desktop during a recorded step failed the run: {quiet_run.stdout[-400:]}")
    need("FAIL [recording-stall]" not in quiet_run.stdout,
         f"the still desktop during a step was failed as a stall: {quiet_run.stdout[-400:]}")
    with open(os.path.join(quiet, "findings.json"), encoding="utf-8") as handle:
        findings = json.load(handle)["findings"]
    still = [finding for finding in findings if finding["kind"] == "frozen-screen"]
    need(still and all(not finding["assertion"] for finding in still),
         f"the still desktop during a step left no informational finding: {findings!r}")


def analysis_capability(panel):
    return next((capability for capability in panel.get("capabilities") or []
                 if capability.get("stage") == "deterministic analysis"), {})


def check_panel_stages(workdir):
    evidence = os.path.join(workdir, "bundle")
    os.makedirs(evidence)
    shutil.copy(build_seconds_video(workdir), os.path.join(evidence, "screen.mov"))
    origin = 1_700_000_000_000
    write_manifest(os.path.join(evidence, "frames.tsv"), origin)
    with open(os.path.join(evidence, "acceptance.txt"), "w", encoding="utf-8") as handle:
        handle.write("artifact: fixture\nverdict: accepted\n")
    with open(os.path.join(evidence, "recording.tsv"), "w", encoding="utf-8") as handle:
        handle.write("12.4\t48\t1234567\t310\n")
    with open(os.path.join(evidence, "journey.log"), "w", encoding="utf-8") as handle:
        handle.write("recording: 999.0s, 9999 frames, 1 bytes, largest gap 9999ms\n")
    solid_png(os.path.join(evidence, "01-first-launch.png"), PALETTE[0])
    solid_png(os.path.join(evidence, "02-home.png"), PALETTE[4])
    with open(os.path.join(evidence, "steps.tsv"), "w", encoding="utf-8") as handle:
        handle.write("2026-10-25T10:00:00Z\t%s\n" % os.path.join(evidence, "01-first-launch"))
        handle.write("2026-10-25T10:00:02Z\t%s\n" % os.path.join(evidence, "02-home"))
    findings = {
        "recording": {"frames": 48, "span_ms": 11750},
        "findings": [{"kind": "screen-change", "severity": "low", "assertion": None,
                      "t_start": origin + 8400, "t_end": origin + 8700,
                      "duration_ms": 300, "note": "fixture flag"}],
    }
    with open(os.path.join(evidence, "findings.json"), "w", encoding="utf-8") as handle:
        json.dump(findings, handle)
    panel = os.path.join(evidence, "panel")
    shutil.rmtree(panel, ignore_errors=True)
    result = subprocess.run(["bash", DESIGN_PANEL, evidence], capture_output=True, text=True,
                            env=dict(os.environ, WID_PANEL_SKIP_MODELS="1"), timeout=300)
    need(result.returncode == 0,
         f"design-panel.sh exited {result.returncode}: {result.stdout[-400:]} {result.stderr[-400:]}")
    need(os.path.exists(os.path.join(panel, "report.html")),
         "the panel wrote no report.html")
    with open(os.path.join(panel, "stage-00-run.json"), encoding="utf-8") as handle:
        run_metadata = json.load(handle)["run"]
    need(run_metadata.get("recording") ==
         "12.4s recorded, 48 frames, 1234567 bytes, largest gap 310ms",
         "the report header did not use recording.tsv: %r" % (run_metadata.get("recording"),))
    with open(os.path.join(panel, "panel.json"), encoding="utf-8") as handle:
        merged = json.load(handle)
    analysis = analysis_capability(merged)
    need(analysis.get("status") == "complete"
         and "1 finding" in (analysis.get("detail") or ""),
         f"the deterministic analysis stage is not labelled by its outcome: {analysis!r}")
    lenses = merged.get("lenses") or []
    need(len(lenses) == 6, f"the panel recorded {len(lenses)} lenses instead of six")
    need(all(lens.get("status") == "unavailable" for lens in lenses),
         "the model-free run did not record every lens as unavailable")
    clips = [name for name in os.listdir(os.path.join(panel, "clip-1"))
             if name.endswith(".png")]
    need(clips, "no flagged clip was cut into the bundle")
    status = run([sys.executable, PANEL_LIB, "status", evidence])
    fields = dict(line.split("=", 1) for line in status.stdout.splitlines() if "=" in line)
    need(fields.get("analysis", "").startswith("complete")
         and "1 finding" in fields.get("analysis", ""),
         f"the host summary does not carry the analysis outcome: {fields.get('analysis')!r}")
    need(fields.get("lenses_complete") == "0",
         f"a model-free panel reported {fields.get('lenses_complete')} completed lenses")
    need(fields.get("reason"), "a model-free panel reported no blocking reason")

    # The reviewer answers with a turn_end text content element, shaped for the stage
    # its prompt asks about and for the lens that prompt named. A stub `pi` on PATH
    # keeps this offline and deterministic while exercising the real panel stages.
    lens_answer = {"lens": "rams", "verdict": "sound", "summary": "quiet and ordered",
                   "findings": []}
    clip_answer = {"verdict": "expected", "severity": "minor",
                   "reason": "the change belongs to the scripted step", "what_to_fix": ""}
    vision_answer = {"next_step_valid": True, "check_step_index": 3,
                     "reason": "the next scripted step still fits this screen"}
    bindir = os.path.join(workdir, "bin")
    os.makedirs(bindir)
    write_pi_stub(
        os.path.join(bindir, "pi"),
        "if 'next_step_valid' in prompt:\n"
        "    answer = " + repr(vision_answer) + "\n"
        "elif 'what_to_fix' in prompt:\n"
        "    answer = " + repr(clip_answer) + "\n"
        "else:\n"
        "    found = re.search(r'lens identifier is \"([a-z]+)\"', prompt)\n"
        "    answer = dict(" + repr(lens_answer) + ", lens=found.group(1) if found else '')\n")
    with_answer = subprocess.run(
        ["bash", DESIGN_PANEL, evidence], capture_output=True, text=True, timeout=300,
        env=dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"],
                 WID_PANEL_MODEL="stub/model"))
    need(with_answer.returncode == 0,
         f"design-panel.sh exited {with_answer.returncode}: {with_answer.stderr[-400:]}")
    with open(os.path.join(panel, "panel.json"), encoding="utf-8") as handle:
        filled = json.load(handle)
    lenses = filled.get("lenses") or []
    need(all(lens.get("status") == "complete" for lens in lenses),
         "a reviewer answer was not parsed into a completed lens: "
         + json.dumps([lens.get("error") for lens in lenses]))
    need([lens.get("lens") for lens in lenses] == REQUIRED_LENSES,
         "the lens stage recorded another lens set: " + json.dumps([lens.get("lens") for lens in lenses]))
    need(all((lens.get("answer") or {}).get("lens") == lens.get("lens") for lens in lenses),
         "a lens record kept an answer for another lens: "
         + json.dumps([(lens.get("lens"), (lens.get("answer") or {}).get("lens")) for lens in lenses]))
    need((lenses[0].get("answer") or {}).get("verdict") == "sound",
         "the lens stage did not keep the reviewer's answer")
    need(all(len((lens.get("answer") or {}).get("findings") or []) == 0 for lens in lenses),
         "the lens stage misread the reviewer's findings list")
    clip_reviews = filled.get("clip_reviews") or []
    need(clip_reviews and clip_reviews[0].get("verdict") == "expected"
         and clip_reviews[0].get("severity") == "minor",
         f"the flagged clip verdict did not survive validation: {clip_reviews}")
    vision_checks = filled.get("vision_checks") or []
    need(vision_checks and vision_checks[0].get("next_step_valid") is True
         and vision_checks[0].get("check_step_index") == 3,
         f"the vision answer did not survive validation: {vision_checks}")
    status = run([sys.executable, PANEL_LIB, "status", evidence, "--require", *REQUIRED_LENSES])
    fields = dict(line.split("=", 1) for line in status.stdout.splitlines() if "=" in line)
    need(fields.get("lenses_complete") == "6",
         f"a fully answered panel reported {fields.get('lenses_complete')} completed lenses")
    need(fields.get("lenses_required_missing") == "",
         f"a fully answered panel reported missing lenses: {fields.get('lenses_required_missing')!r}")
    need("reason=" not in status.stdout, "a fully answered panel still reported a blocking reason")

    # Known-broken: every prompt answered with the Rams review. That is one review
    # repeated, so no lens may count and the six-lens gate must stay blocked.
    fixed_bindir = os.path.join(workdir, "fixed-bin")
    os.makedirs(fixed_bindir)
    write_pi_stub(os.path.join(fixed_bindir, "pi"),
                  "answer = " + repr(dict(lens_answer, lens="rams")) + "\n")
    repeated = subprocess.run(
        ["bash", DESIGN_PANEL, evidence], capture_output=True, text=True, timeout=300,
        env=dict(os.environ, PATH=fixed_bindir + os.pathsep + os.environ["PATH"],
                 WID_PANEL_MODEL="stub/model"))
    need(repeated.returncode == 0,
         f"design-panel.sh exited {repeated.returncode}: {repeated.stderr[-400:]}")
    with open(os.path.join(panel, "panel.json"), encoding="utf-8") as handle:
        repeated_panel = json.load(handle)
    lenses = repeated_panel.get("lenses") or []
    need(len(lenses) == 6 and [lens.get("status") for lens in lenses]
         == ["complete"] + ["unavailable"] * 5,
         "one review repeated for every lens counted as the six lenses: "
         + json.dumps([(lens.get("lens"), lens.get("status")) for lens in lenses]))
    status = run([sys.executable, PANEL_LIB, "status", evidence, "--require", *REQUIRED_LENSES])
    fields = dict(line.split("=", 1) for line in status.stdout.splitlines() if "=" in line)
    need(fields.get("lenses_complete") == "1",
         f"a repeated single-lens answer reported {fields.get('lenses_complete')} completed lenses")
    need(fields.get("lenses_required_missing") == " ".join(REQUIRED_LENSES[1:]),
         f"the repeated answer satisfied the required set: {fields.get('lenses_required_missing')!r}")

    def panel_run():
        completed = subprocess.run(["bash", DESIGN_PANEL, evidence], capture_output=True,
                                   text=True, timeout=300,
                                   env=dict(os.environ, WID_PANEL_SKIP_MODELS="1"))
        need(completed.returncode == 0,
             f"design-panel.sh exited {completed.returncode}: {completed.stderr[-400:]}")
        with open(os.path.join(panel, "panel.json"), encoding="utf-8") as handle:
            loaded = json.load(handle)
        with open(os.path.join(panel, "report.html"), encoding="utf-8") as handle:
            return loaded, handle.read()

    # Known-broken: a missing, refused or unreadable analysis was labelled complete.
    os.remove(os.path.join(evidence, "findings.json"))
    without_analysis, report = panel_run()
    analysis = analysis_capability(without_analysis)
    need(analysis.get("status") == "failed",
         f"a missing analysis was labelled {analysis.get('status')!r} instead of a failure")
    need("findings.json is missing" in (analysis.get("detail") or ""),
         f"the failure does not name the reason: {analysis.get('detail')!r}")
    need(any("deterministic analysis did not complete" in gap
             for gap in without_analysis.get("declared_gaps") or []),
         f"the bundle does not declare the missing analysis: {without_analysis.get('declared_gaps')!r}")
    need("findings.json is missing" in report,
         "the report hides why the deterministic analysis did not run")
    _, fields = status_fields(evidence)
    need(fields.get("analysis", "").startswith("failed")
         and "findings.json is missing" in fields.get("analysis", ""),
         f"the host summary does not carry the missing analysis: {fields.get('analysis')!r}")

    refused_reason = ("the frame stream decoded to 5 images for 6 recorded frames: "
                      "a capture is missing")
    with open(os.path.join(evidence, "findings.json"), "w", encoding="utf-8") as handle:
        json.dump({"recording": {"error": refused_reason}, "findings": []}, handle)
    refused_panel, report = panel_run()
    analysis = analysis_capability(refused_panel)
    need(analysis.get("status") == "failed",
         f"an analyser refusal was labelled {analysis.get('status')!r} instead of a failure")
    need(refused_reason in (analysis.get("detail") or ""),
         f"the failure does not carry the analyser's reason: {analysis.get('detail')!r}")
    need(any(refused_reason in gap for gap in refused_panel.get("declared_gaps") or []),
         f"the bundle does not declare the analyser's refusal: {refused_panel.get('declared_gaps')!r}")
    need(refused_reason in report, "the report hides the analyser's failure reason")
    _, fields = status_fields(evidence)
    need(fields.get("analysis", "").startswith("failed")
         and refused_reason in fields.get("analysis", ""),
         f"the host summary does not carry the analyser's refusal: {fields.get('analysis')!r}")

    with open(os.path.join(evidence, "findings.json"), "w", encoding="utf-8") as handle:
        handle.write("{ this is not the analyser output\n")
    broken_panel, report = panel_run()
    analysis = analysis_capability(broken_panel)
    need(analysis.get("status") == "failed",
         f"an unreadable analysis was labelled {analysis.get('status')!r} instead of a failure")
    need("could not be read" in (analysis.get("detail") or ""),
         f"the unreadable analysis gives no reason: {analysis.get('detail')!r}")
    need("could not be read" in report, "the report hides that the analysis file is unreadable")
    _, fields = status_fields(evidence)
    need(fields.get("analysis", "").startswith("failed")
         and "could not be read" in fields.get("analysis", ""),
         f"the host summary does not carry the unreadable analysis: {fields.get('analysis')!r}")


def repository_root(path):
    result = subprocess.run(["git", "-C", path, "rev-parse", "--show-toplevel"],
                            capture_output=True, text=True)
    need(result.returncode == 0, f"git rev-parse failed: {result.stderr[:200]}")
    return result.stdout.strip()


def tracked_paths(start):
    root = repository_root(start)
    listing = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True)
    need(listing.returncode == 0, f"git ls-files failed: {listing.stderr[:200]}")
    return root, [path for path in listing.stdout.split("\n") if path]


def run_entry_point(workdir, name, script, arguments, shim):
    layout = os.path.join(workdir, name)
    os.makedirs(layout)
    shutil.copy(script, os.path.join(layout, os.path.basename(script)))
    if shim is not None:
        target = os.path.join(layout, shim)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy(os.path.join(HERE, "vm", "launchd-host.sh"), target)
    return subprocess.run(["/bin/bash", os.path.join(layout, os.path.basename(script))] + arguments,
                          capture_output=True, text=True, timeout=60,
                          env=dict(os.environ, PATH="/usr/bin:/bin", WID_VM_NO_LAUNCHD="1"))


def assert_shim_contract(workdir, name, script, arguments, shim, prefix, next_work):
    missing = run_entry_point(workdir, name + "-missing", script, arguments, None)
    need(missing.returncode != 0,
         f"{os.path.basename(script)} did not stop when the launchd shim was missing")
    complaints = [line for line in missing.stderr.splitlines() if "launchd-host.sh" in line]
    need(any(line.startswith(prefix) for line in complaints),
         f"the missing launchd shim was not reported as a setup failure: {missing.stderr[-400:]!r}")
    need(not any(next_work in line for line in missing.stderr.splitlines()),
         f"{os.path.basename(script)} went on to its next step after the launchd shim failed")

    loaded = run_entry_point(workdir, name + "-loaded", script, arguments, shim)
    need(loaded.returncode != 0 and next_work in loaded.stderr,
         f"the launchd shim at {shim} did not load: {loaded.stderr[-400:]!r}")
    need("could not load" not in loaded.stderr
         and "wid_launchd_reexec is missing" not in loaded.stderr,
         f"a present launchd shim was reported missing: {loaded.stderr[-400:]!r}")


def check_prepare_guest_shim(workdir):
    assert_shim_contract(workdir, "prepare-guest", PREPARE_GUEST, [], "launchd-host.sh",
                         "prepare-guest: ERROR:", "tart is not installed")


def check_journey_shim(workdir):
    artifact = os.path.join(workdir, "fixture.dmg")
    with open(artifact, "w", encoding="utf-8") as handle:
        handle.write("fixture\n")
    assert_shim_contract(workdir, "vm-journey", VM_JOURNEY, [artifact], "vm/launchd-host.sh",
                         "vm-journey: ERROR:", "tart is not installed")


def check_tracked_bytecode(workdir):
    root, tracked = tracked_paths(HERE)
    offenders = tracked_bytecode(tracked)
    need(not offenders,
         "generated bytecode is tracked: " + ", ".join(offenders[:5]))
    need(os.path.relpath(os.path.abspath(__file__), root) in tracked,
         "the guard did not list this test file from the repository root, so its listing is not repo-wide")

    scratch = os.path.join(workdir, "scratch")
    for relative in ("rig/tool.py", "other/tool.py",
                     "other/__pycache__/helper.cpython-314.pyc", "other/legacy.pyo"):
        target = os.path.join(scratch, relative)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf-8") as handle:
            handle.write("# fixture\n")
    for command in (["init", "-q"], ["add", "-A", "-f"]):
        result = subprocess.run(["git", "-C", scratch] + command, capture_output=True, text=True)
        need(result.returncode == 0,
             f"could not build the scratch repository: {result.stderr[:300]}")
    _, scratch_tracked = tracked_paths(os.path.join(scratch, "rig"))
    need("other/__pycache__/helper.cpython-314.pyc" in scratch_tracked
         and "other/legacy.pyo" in scratch_tracked,
         "the guard read only the directory it was called from: %r" % (scratch_tracked,))
    need(tracked_bytecode(scratch_tracked)
         == ["other/__pycache__/helper.cpython-314.pyc", "other/legacy.pyo"],
         "the guard did not flag the bytecode in a scratch repository: %r"
         % (tracked_bytecode(scratch_tracked),))
    scoped = subprocess.run(["git", "-C", os.path.join(scratch, "rig"), "ls-files"],
                            capture_output=True, text=True)
    scoped_paths = [path for path in scoped.stdout.split("\n") if path]
    need(scoped.returncode == 0 and "tool.py" in scoped_paths
         and not tracked_bytecode(scoped_paths),
         "the subtree-scoped listing should hide the bytecode it does not look at: %r"
         % (scoped_paths,))


def check_launchd_forwarding(workdir):
    probe = os.path.join(workdir, "probe.sh")
    with open(probe, "w", encoding="utf-8") as handle:
        handle.write("#!/bin/bash\nset -uo pipefail\n. \"$1\"\nwid_launchd_forwarded\n")
    result = subprocess.run(["/bin/bash", probe, os.path.join(HERE, "vm", "launchd-host.sh")],
                            capture_output=True, text=True, timeout=60,
                            env={"PATH": "/usr/bin:/bin", "HOME": "/Users/probe",
                                 "WID_VM_ROOT": "/vm",
                                 "WID_PANEL_MODEL": "openai-codex/gpt-6-astra",
                                 "WID_PANEL_SKIP_MODELS": "1",
                                 "ANTHROPIC_API_KEY": "sk-test",
                                 "OPENAI_BASE_URL": "https://example.invalid",
                                 "HTTPS_PROXY": "http://proxy.invalid:3128",
                                 "PI_OFFLINE": "1",
                                 "UNRELATED_SECRET": "not-for-the-job"})
    need(result.returncode == 0,
         f"the launchd shim could not list its environment: {result.stderr[-300:]!r}")
    forwarded = set(result.stdout.split())
    need({"PATH", "HOME", "WID_VM_ROOT", "WID_PANEL_MODEL", "WID_PANEL_SKIP_MODELS",
          "ANTHROPIC_API_KEY", "OPENAI_BASE_URL", "HTTPS_PROXY", "PI_OFFLINE"} <= forwarded,
         f"the launchd job would lose panel inputs: {sorted(forwarded)}")
    need("UNRELATED_SECRET" not in forwarded,
         "the launchd job would receive variables nobody asked it to forward")


def check_review_record_extra_lens(workdir):
    evidence = os.path.join(workdir, "seven lenses")
    os.makedirs(evidence)
    with open(os.path.join(evidence, "acceptance.txt"), "w", encoding="utf-8") as handle:
        handle.write("artifact: fixture\nverdict: accepted\n")
    with open(os.path.join(evidence, "recording.tsv"), "w", encoding="utf-8") as handle:
        handle.write("12.4\t48\t1234567\t310\n")
    with open(os.path.join(evidence, "findings.json"), "w", encoding="utf-8") as handle:
        json.dump({"recording": {"frames": 48, "span_ms": 11750}, "findings": []}, handle)
    bindir = os.path.join(workdir, "bin")
    os.makedirs(bindir)
    write_pi_stub(os.path.join(bindir, "pi"),
                  "found = re.search(r'lens identifier is \"([a-z]+)\"', prompt)\n"
                  "answer = dict({\"lens\": 'rams', \"verdict\": \"sound\", \"summary\": \"quiet\", "
                  "\"findings\": []}, lens=found.group(1) if found else '')\n")
    extra = REQUIRED_LENSES + ["contrast"]
    completed = subprocess.run(
        ["bash", DESIGN_PANEL, evidence], capture_output=True, text=True, timeout=300,
        env=dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"],
                 WID_PANEL_MODEL="stub/model",
                 WID_PANEL_LENSES=" ".join(extra),
                 WID_PANEL_REQUIRED=" ".join(REQUIRED_LENSES)))
    need(completed.returncode == 0,
         f"design-panel.sh exited {completed.returncode}: {completed.stderr[-400:]}")
    with open(os.path.join(evidence, "acceptance.txt"), encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    need("panel: complete" in lines,
         f"an extra lens turned a complete review into a refusal: {lines!r}")
    need("panel_lenses_complete: 7/7" in lines,
         f"the record does not carry every lens it ran: {lines!r}")
    need("sign_off: accepted" in lines,
         f"a complete review over the six required lenses did not sign off: {lines!r}")
    need(not any(line.startswith("panel_not_run:") for line in lines),
         f"a complete review carried a refusal reason: {lines!r}")
    gate = run([sys.executable, PANEL_LIB, "gate", evidence])
    need(gate.stdout.strip() == "0",
         f"a complete seven-lens review would fail the panel gate: {gate.stdout!r}")

    renamed = os.path.join(workdir, "renamed lens")
    os.makedirs(renamed)
    with open(os.path.join(renamed, "acceptance.txt"), "w", encoding="utf-8") as handle:
        handle.write("artifact: fixture\nverdict: accepted\n")
    with open(os.path.join(renamed, "recording.tsv"), "w", encoding="utf-8") as handle:
        handle.write("12.4\t48\t1234567\t310\n")
    with open(os.path.join(renamed, "findings.json"), "w", encoding="utf-8") as handle:
        json.dump({"recording": {"frames": 48, "span_ms": 11750}, "findings": []}, handle)
    renamed_run = subprocess.run(
        ["bash", DESIGN_PANEL, renamed], capture_output=True, text=True, timeout=300,
        env=dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"],
                 WID_PANEL_MODEL="stub/model",
                 WID_PANEL_LENSES=" ".join(["rams", "norman", "spiekermann", "kare",
                                            "matas", "vigneli"]),
                 WID_PANEL_REQUIRED=" ".join(REQUIRED_LENSES)))
    need(renamed_run.returncode == 0,
         f"design-panel.sh exited {renamed_run.returncode}: {renamed_run.stderr[-400:]}")
    with open(os.path.join(renamed, "acceptance.txt"), encoding="utf-8") as handle:
        renamed_lines = handle.read().splitlines()
    need("panel: not run" in renamed_lines,
         f"a renamed lens list signed off without its required name: {renamed_lines!r}")
    gate = run([sys.executable, PANEL_LIB, "gate", renamed])
    need(gate.stdout.strip() == "79",
         f"a review missing a required lens would pass the panel gate: {gate.stdout!r}")

    with open(os.path.join(evidence, "acceptance.txt"), "w", encoding="utf-8") as handle:
        handle.write("artifact: fixture\nverdict: rejected\n")
    recorded = subprocess.run([sys.executable, PANEL_LIB, "record", evidence],
                              capture_output=True, text=True, timeout=120)
    need(recorded.returncode == 0, f"record failed: {recorded.stderr[:300]}")
    with open(os.path.join(evidence, "acceptance.txt"), encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    need("sign_off: not accepted - an assertion or the recording failed" in lines,
         f"a rejected run recorded an accepted sign-off: {lines!r}")
    gate = run([sys.executable, PANEL_LIB, "gate", evidence])
    need(gate.stdout.strip() == "0",
         f"a rejected run with a complete review broke the panel gate: {gate.stdout!r}")


def check_widrig_timeout(workdir):
    binary = os.path.join(workdir, "widrig")
    build = subprocess.run(["swiftc", "-O", "-target", "arm64-apple-macos14.0", "-o", binary,
                            WIDRIG], capture_output=True, text=True, timeout=300)
    need(build.returncode == 0, f"widrig did not build: {build.stderr[-400:]}")
    started = time.monotonic()
    found = subprocess.run([binary, "find", "--pid", "999999", "--role", "AXButton",
                            "--timeout", "1"], capture_output=True, text=True, timeout=30)
    elapsed = time.monotonic() - started
    need(found.returncode == 1,
         f"find on a missing element exited {found.returncode}: {found.stderr[-200:]!r}")
    need(json.loads(found.stdout) == {"found": False},
         f"find did not report a timeout result: {found.stdout!r}")
    need(elapsed >= 0.9,
         f"find took a one-shot snapshot instead of waiting its timeout: {elapsed:.2f}s")


def check_declared_gap_remedy(workdir):
    evidence = os.path.join(workdir, "a bundle with spaces")
    os.makedirs(evidence)
    with open(os.path.join(evidence, "acceptance.txt"), "w", encoding="utf-8") as handle:
        handle.write("artifact: fixture\nverdict: accepted\n")
    with open(os.path.join(evidence, "recording.tsv"), "w", encoding="utf-8") as handle:
        handle.write("12.4\t48\t1234567\t310\n")
    with open(os.path.join(evidence, "findings.json"), "w", encoding="utf-8") as handle:
        json.dump({"recording": {"frames": 48, "span_ms": 11750}, "findings": []}, handle)
    bindir = os.path.join(workdir, "bin")
    os.makedirs(bindir)
    failing = os.path.join(bindir, "pi")
    with open(failing, "w", encoding="utf-8") as handle:
        handle.write("#!/bin/bash\nexit 1\n")
    os.chmod(failing, 0o755)
    blocked = subprocess.run(
        ["bash", DESIGN_PANEL, evidence], capture_output=True, text=True, timeout=300,
        env=dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"],
                 WID_PANEL_MODEL="stub/model", WID_PANEL_ALTERNATES="stub/alternate",
                 WID_PANEL_ATTEMPTS="1", WID_PANEL_BACKOFF="0"))
    need(blocked.returncode == 0,
         f"design-panel.sh exited {blocked.returncode}: {blocked.stderr[-400:]}")
    with open(os.path.join(evidence, "panel", "panel.json"), encoding="utf-8") as handle:
        gaps = json.load(handle).get("declared_gaps") or []
    gap = next((text for text in gaps if "Re-run: " in text), "")
    need(gap, f"the no-reviewer gap carries no remedy: {gaps!r}")
    remedy = gap.split("Re-run: ", 1)[1]
    parsed = subprocess.run(["/bin/sh", "-c", "set -- " + remedy + '; printf \'%s\\n\' "$@"'],
                            capture_output=True, text=True, timeout=60)
    arguments = parsed.stdout.split("\n")[:-1]
    need(arguments == ["bash", DESIGN_PANEL, os.path.realpath(evidence)],
         f"the declared-gap remedy does not survive a shell parse: {arguments!r}")
    with open(os.path.join(evidence, "acceptance.txt"), encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    need("panel_command: " + remedy in lines,
         f"the bundle carries two different remedies: {lines!r} vs {remedy!r}")


def check_review_record_remedy(workdir):
    evidence = os.path.join(workdir, "a bundle with spaces")
    os.makedirs(evidence)
    with open(os.path.join(evidence, "acceptance.txt"), "w", encoding="utf-8") as handle:
        handle.write("artifact: fixture\nverdict: accepted\n")
    with open(os.path.join(evidence, "recording.tsv"), "w", encoding="utf-8") as handle:
        handle.write("12.4\t48\t1234567\t310\n")
    with open(os.path.join(evidence, "findings.json"), "w", encoding="utf-8") as handle:
        json.dump({"recording": {"frames": 48, "span_ms": 11750}, "findings": []}, handle)

    blocked = subprocess.run(["bash", DESIGN_PANEL, evidence], capture_output=True, text=True,
                             timeout=300, env=dict(os.environ, WID_PANEL_SKIP_MODELS="1"))
    need(blocked.returncode == 0,
         f"design-panel.sh exited {blocked.returncode}: {blocked.stderr[-400:]}")
    with open(os.path.join(evidence, "acceptance.txt"), encoding="utf-8") as handle:
        record = handle.read()
    blocked_lines = record.splitlines()
    need("panel: not run" in blocked_lines,
         f"a model-free run did not record a blocked review: {record!r}")
    need(any(line.startswith("sign_off: blocked - the six-lens review did not run")
             for line in blocked_lines),
         f"a model-free run did not block its sign-off: {record!r}")
    remedy = next((line.split(":", 1)[1].strip() for line in blocked_lines
                   if line.startswith("panel_command:")), "")
    need("bash " in remedy and "design-panel.sh" in remedy,
         f"the blocked record prints no re-run command: {remedy!r}")
    parsed = subprocess.run(["/bin/sh", "-c", "set -- " + remedy + '; printf \'%s\\n\' "$@"'],
                            capture_output=True, text=True, timeout=60)
    arguments = parsed.stdout.split("\n")[:-1]
    need(arguments == ["bash", DESIGN_PANEL, os.path.realpath(evidence)],
         f"the recorded remedy does not survive a shell parse: {arguments!r}")

    bindir = os.path.join(workdir, "bin")
    os.makedirs(bindir)
    write_pi_stub(os.path.join(bindir, "pi"),
                  "found = re.search(r'lens identifier is \"([a-z]+)\"', prompt)\n"
                  "answer = dict({\"lens\": 'rams', \"verdict\": \"sound\", \"summary\": \"quiet\", "
                  "\"findings\": []}, lens=found.group(1) if found else '')\n")
    replayed = subprocess.run(["/bin/sh", "-c", remedy], capture_output=True, text=True,
                              timeout=300,
                              env=dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"]))
    need(replayed.returncode == 0,
         f"the recorded remedy failed: {replayed.stderr[-400:]!r}")

    with open(os.path.join(evidence, "acceptance.txt"), encoding="utf-8") as handle:
        refreshed = handle.read()
    lines = refreshed.splitlines()
    need("artifact: fixture" in lines and "verdict: accepted" in lines,
         f"the remedy lost the run's own lines: {refreshed!r}")
    need("panel: complete" in lines,
         f"the remedy did not refresh the panel state: {refreshed!r}")
    need("panel_lenses_complete: 6/6" in lines,
         f"the remedy did not record six complete lenses: {refreshed!r}")
    need(sum(1 for line in lines
             if line.startswith("panel_lens: ") and "\tcomplete\t" in line) == 6,
         f"the remedy left stale per-lens lines: {refreshed!r}")
    need("sign_off: accepted" in lines,
         f"the refreshed record does not match the artifact: {refreshed!r}")
    need(not any(line.startswith("panel_not_run:") for line in lines),
         f"the stale blocked reason survived the remedy: {refreshed!r}")
    need(any(line.startswith("analysis: complete (") for line in lines),
         f"the refreshed record lost the analysis outcome: {refreshed!r}")
    provenance = next((line for line in lines if line.startswith("review: ")), "")
    need(re.search(r"design-panel re-run at \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", provenance)
         and "does not re-validate the product" in provenance,
         f"the re-run left no provenance with a timestamp: {provenance!r}")
    lens_results = next((line for line in lines if line.startswith("review_lenses: ")), "")
    need(all(name + "=complete:" in lens_results for name in REQUIRED_LENSES),
         f"the provenance does not carry the lens results: {lens_results!r}")
    with open(os.path.join(evidence, "notes.md"), encoding="utf-8") as handle:
        notes = handle.read()
    need("## Review record updated after the run" in notes,
         "the bundle notes do not say the review was updated after the run")


CHECKS = [
    ("model answers are validated before they count", check_answer_validation),
    ("generated bytecode is not tracked", check_tracked_bytecode),
    ("guest setup stops when the launchd shim is missing", check_prepare_guest_shim),
    ("the recorded journey stops when the launchd shim is missing", check_journey_shim),
    ("flagged clip lands on the flagged second", check_clip_origin),
    ("analyser fails on a dropped capture", check_analyser_alignment),
    ("a recording whose screen never changes fails", check_frozen_recording),
    ("launch assertion ids are keyed to their stream", check_launch_assertion_ids),
    ("lens summary reports completeness and reason", check_lens_status),
    ("design panel writes its stages from a bundle", check_panel_stages),
    ("a blocked review record is refreshed by its printed remedy", check_review_record_remedy),
    ("the launchd job receives the panel's environment", check_launchd_forwarding),
    ("the review record and the panel gate agree", check_review_record_extra_lens),
    ("the declared-gap remedy is one pasteable command", check_declared_gap_remedy),
    ("widrig find waits for its timeout", check_widrig_timeout),
]


def main():
    failures = 0
    with tempfile.TemporaryDirectory(prefix="wid-rig-test.") as workdir:
        for index, (name, check) in enumerate(CHECKS):
            case = os.path.join(workdir, f"case-{index}")
            os.makedirs(case)
            try:
                check(case)
            except AssertionError as error:
                failures += 1
                print(f"FAIL {name}: {error}")
            else:
                print(f"PASS {name}")
    print(f"test-vm-rig: {len(CHECKS) - failures} of {len(CHECKS)} checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
