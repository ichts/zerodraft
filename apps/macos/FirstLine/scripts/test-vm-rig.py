#!/usr/bin/env python3
"""Executable checks for the recorded-acceptance rig's shared boundaries.

[INPUT] None. Requires ffmpeg, python3 and (for one known-broken probe) jq, which the
        rig itself requires.
[OUTPUT] One PASS/FAIL line per check on stdout; exit 0 only when every check passes.
[POS] apps/macos/FirstLine/scripts/test-vm-rig.py - drives the pieces the VM journey
      and the design panel share: the panel answer parser, the recording-relative clip
      seek, the analyser's frame alignment, and the lens summary the host verdict reads.
[PROTOCOL] Every check runs the real executable on a fixture and asserts its observable
           output; nothing here greps the scripts' source. The known-broken cases feed
           the previous behaviour (a manifest whose first stamp is the pre-recording
           span, a dropped capture, the old jq content filter) and must fail, so a
           regression reopens the finding.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PANEL_LIB = os.path.join(HERE, "vm", "panel-lib.py")
ANALYSER = os.path.join(HERE, "vm", "analyse-recording.py")
DESIGN_PANEL = os.path.join(HERE, "design-panel.sh")
# The acceptance contract's lens set, as vm-journey.sh states it.
REQUIRED_LENSES = ["rams", "norman", "spiekermann", "kare", "matas", "vignelli"]

# Twelve solid colours with enough separation to tell neighbouring seconds apart after
# JPEG compression and an H.264 round trip.
PALETTE = ["000000", "ffffff", "cc2214", "1f8f3c", "2b46c8", "e0c020",
           "b02f9a", "159fa8", "e07a1e", "6b2fa0", "808080", "144d28"]


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


def model_verdict(stream, stage):
    with open(stream, encoding="utf-8") as handle:
        result = run([sys.executable, PANEL_LIB, "verdict", stage], stdin=handle.read())
    need(result.returncode == 0, f"verdict {stage} failed: {result.stderr[:200]}")
    return json.loads(result.stdout)


def check_answer_validation(workdir):
    stream = os.path.join(workdir, "lens.jsonl")
    payload = {"lens": "rams", "verdict": "sound", "summary": "quiet and ordered",
               "findings": []}
    write_answer_stream(stream, json.dumps(payload))
    accepted = model_verdict(stream, "lens")
    need(accepted["status"] == "complete",
         f"a well-formed lens review was rejected: {accepted}")
    need(accepted["answer"]["lens"] == "rams" and accepted["answer"]["verdict"] == "sound",
         f"the validated answer lost its fields: {accepted['answer']}")

    # Any JSON object used to count as a completed lens. It must not: this is not a
    # lens review, and a lens may only count once it answered as a lens.
    not_a_review = os.path.join(workdir, "not-a-review.jsonl")
    write_answer_stream(not_a_review, json.dumps({"error": "cannot read images"}))
    rejected = model_verdict(not_a_review, "lens")
    need(rejected["status"] == "unavailable",
         f"a non-lens JSON object counted as a reviewed lens: {rejected}")
    need("lens" in rejected["error"],
         f"the rejection does not name the missing field: {rejected['error']!r}")

    # A turn that ended abnormally is not an answer even when its JSON parses.
    truncated = os.path.join(workdir, "truncated.jsonl")
    write_answer_stream(truncated, json.dumps(payload), stop_reason="length")
    cut = model_verdict(truncated, "lens")
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


def check_lens_status(workdir):
    evidence = os.path.join(workdir, "panel-evidence")
    panel = os.path.join(evidence, "panel")
    os.makedirs(panel)
    required = REQUIRED_LENSES
    stage = {"lenses": [
        {"lens": "rams", "status": "complete", "model": "fixture",
         "answer": {"verdict": "sound", "findings": [{"severity": "nit", "title": "x"}]}},
        {"lens": "norman", "status": "unavailable", "error": "no reviewer model answered"},
    ]}
    with open(os.path.join(panel, "stage-04-lenses.json"), "w", encoding="utf-8") as handle:
        json.dump(stage, handle)
    with open(os.path.join(panel, "stage-05-capabilities.json"), "w", encoding="utf-8") as handle:
        json.dump({"declared_gaps": [
            "Gemini route cursor/gemini-4-argon is unavailable on this machine: no answer."]}, handle)
    partial = run([sys.executable, PANEL_LIB, "status", evidence, "--require", *required])
    need(partial.returncode == 0, f"status failed: {partial.stderr[:200]}")
    fields = dict(line.split("=", 1) for line in partial.stdout.splitlines() if "=" in line)
    need(fields.get("lenses_total") == "2", f"wrong total: {fields.get('lenses_total')!r}")
    need(fields.get("lenses_complete") == "1", f"wrong completed count: {fields.get('lenses_complete')!r}")
    need(fields.get("lenses_required_missing") == "norman spiekermann kare matas vignelli",
         f"the required set is not checked by name: {fields.get('lenses_required_missing')!r}")
    need("no reviewer model answered" in fields.get("reason", ""),
         "an incomplete lens stage reported no reason")
    need("Gemini" not in fields.get("reason", ""),
         f"the blocking reason named an unrelated capability gap: {fields.get('reason')!r}")
    rams = [line for line in partial.stdout.splitlines() if line.startswith("lens=rams")]
    need(rams and rams[0].split("\t")[1:] == ["complete", "sound", "1", ""],
         f"the rams lens line is wrong: {rams!r}")

    stage["lenses"][1] = {"lens": "norman", "status": "unavailable"}
    with open(os.path.join(panel, "stage-04-lenses.json"), "w", encoding="utf-8") as handle:
        json.dump(stage, handle)
    gapped = run([sys.executable, PANEL_LIB, "status", evidence, "--require", *required])
    fields = dict(line.split("=", 1) for line in gapped.stdout.splitlines() if "=" in line)
    need(fields.get("reason", "").startswith("Gemini route"),
         f"the declared gap is not the fallback reason: {fields.get('reason')!r}")

    stage["lenses"] = [{"lens": name, "status": "complete",
                        "answer": {"verdict": "needs work", "findings": []}}
                       for name in required]
    with open(os.path.join(panel, "stage-04-lenses.json"), "w", encoding="utf-8") as handle:
        json.dump(stage, handle)
    complete = run([sys.executable, PANEL_LIB, "status", evidence, "--require", *required])
    fields = dict(line.split("=", 1) for line in complete.stdout.splitlines() if "=" in line)
    need(fields.get("lenses_required_missing") == "",
         f"a complete required set reported missing lenses: {fields.get('lenses_required_missing')!r}")
    need("reason=" not in complete.stdout,
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
    lenses = merged.get("lenses") or []
    need(len(lenses) == 6, f"the panel recorded {len(lenses)} lenses instead of six")
    need(all(lens.get("status") == "unavailable" for lens in lenses),
         "the model-free run did not record every lens as unavailable")
    clips = [name for name in os.listdir(os.path.join(panel, "clip-1"))
             if name.endswith(".png")]
    need(clips, "no flagged clip was cut into the bundle")
    status = run([sys.executable, PANEL_LIB, "status", evidence])
    fields = dict(line.split("=", 1) for line in status.stdout.splitlines() if "=" in line)
    need(fields.get("lenses_complete") == "0",
         f"a model-free panel reported {fields.get('lenses_complete')} completed lenses")
    need(fields.get("reason"), "a model-free panel reported no blocking reason")

    # The reviewer answers with a turn_end text content element, shaped for the stage
    # its prompt asks about. A stub `pi` on PATH keeps this offline and deterministic
    # while exercising the real panel stages and their validation.
    lens_answer = {"lens": "rams", "verdict": "sound", "summary": "quiet and ordered",
                   "findings": []}
    clip_answer = {"verdict": "expected", "severity": "minor",
                   "reason": "the change belongs to the scripted step", "what_to_fix": ""}
    vision_answer = {"next_step_valid": True, "check_step_index": 3,
                     "reason": "the next scripted step still fits this screen"}
    bindir = os.path.join(workdir, "bin")
    os.makedirs(bindir)
    stub = os.path.join(bindir, "pi")
    with open(stub, "w", encoding="utf-8") as handle:
        handle.write("#!/usr/bin/env python3\n")
        handle.write("import json, sys\n")
        handle.write("prompt = sys.argv[-1]\n")
        handle.write("if 'next_step_valid' in prompt:\n")
        handle.write("    answer = " + repr(vision_answer) + "\n")
        handle.write("elif 'what_to_fix' in prompt:\n")
        handle.write("    answer = " + repr(clip_answer) + "\n")
        handle.write("else:\n")
        handle.write("    answer = " + repr(lens_answer) + "\n")
        handle.write("print(json.dumps({'type': 'turn_end', 'message': {'stopReason': 'stop',"
                     " 'content': [{'type': 'text', 'text': json.dumps(answer)}]}}))\n")
    os.chmod(stub, 0o755)
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


CHECKS = [
    ("model answers are validated before they count", check_answer_validation),
    ("flagged clip lands on the flagged second", check_clip_origin),
    ("analyser fails on a dropped capture", check_analyser_alignment),
    ("launch assertion ids are keyed to their stream", check_launch_assertion_ids),
    ("lens summary reports completeness and reason", check_lens_status),
    ("design panel writes its stages from a bundle", check_panel_stages),
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
