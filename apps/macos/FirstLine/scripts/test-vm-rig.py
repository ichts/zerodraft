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

# Twelve solid colours with enough separation to tell neighbouring seconds apart after
# JPEG compression and an H.264 round trip.
PALETTE = ["000000", "ffffff", "cc2214", "1f8f3c", "2b46c8", "e0c020",
           "b02f9a", "159fa8", "e07a1e", "6b2fa0", "808080", "144d28"]
CHANNEL_TOLERANCE = 70


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


def write_answer_stream(path, text):
    records = [
        {"type": "message_start"},
        {"type": "turn_end", "message": {"stopReason": "tool_use", "content": [
            {"type": "tool_result", "toolCallId": "1", "output": "no answer yet"}]}},
        {"type": "message_end", "message": {"errorMessage": ""}},
        {"type": "turn_end", "message": {"stopReason": "stop", "content": [
            {"type": "thinking", "text": ""},
            {"type": "text", "text": text}]}},
    ]
    with open(path, "w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record) + "\n")


def check_answer_parser(workdir):
    stream = os.path.join(workdir, "lens.jsonl")
    payload = {"lens": "rams", "verdict": "sound", "summary": "quiet and ordered",
               "findings": []}
    write_answer_stream(stream, json.dumps(payload))
    with open(stream, encoding="utf-8") as handle:
        parsed = run([sys.executable, PANEL_LIB, "answer"], stdin=handle.read())
    need(parsed.returncode == 0, f"answer failed: {parsed.stderr[:200]}")
    need(parsed.stdout.strip() == json.dumps(payload, sort_keys=True)
         or json.loads(parsed.stdout) == payload,
         f"the answer parser returned {parsed.stdout!r} instead of the text content")
    if shutil.which("jq") is None:
        print("SKIP the previous jq content filter probe: jq is not installed")
        return
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
    stage = {"lenses": [
        {"lens": "rams", "status": "complete", "model": "fixture",
         "answer": {"verdict": "sound", "findings": [{"severity": "nit", "title": "x"}]}},
        {"lens": "norman", "status": "unavailable", "error": "no reviewer model answered"},
    ]}
    with open(os.path.join(panel, "stage-04-lenses.json"), "w", encoding="utf-8") as handle:
        json.dump(stage, handle)
    partial = run([sys.executable, PANEL_LIB, "status", evidence])
    need(partial.returncode == 0, f"status failed: {partial.stderr[:200]}")
    fields = dict(line.split("=", 1) for line in partial.stdout.splitlines() if "=" in line)
    need(fields.get("lenses_total") == "2", f"wrong total: {fields.get('lenses_total')!r}")
    need(fields.get("lenses_complete") == "1", f"wrong completed count: {fields.get('lenses_complete')!r}")
    need("no reviewer model answered" in fields.get("reason", ""),
         "an incomplete lens stage reported no reason")
    rams = [line for line in partial.stdout.splitlines() if line.startswith("lens=rams")]
    need(rams and rams[0].split("\t")[1:] == ["complete", "sound", "1", ""],
         f"the rams lens line is wrong: {rams!r}")

    with open(os.path.join(panel, "stage-05-capabilities.json"), "w", encoding="utf-8") as handle:
        json.dump({"declared_gaps": ["No reviewer model answered from this lane."]}, handle)
    gapped = run([sys.executable, PANEL_LIB, "status", evidence])
    fields = dict(line.split("=", 1) for line in gapped.stdout.splitlines() if "=" in line)
    need(fields.get("reason") == "No reviewer model answered from this lane.",
         f"the declared gap is not the reported reason: {fields.get('reason')!r}")

    stage["lenses"][1] = {"lens": "norman", "status": "complete",
                          "answer": {"verdict": "needs work", "findings": []}}
    with open(os.path.join(panel, "stage-04-lenses.json"), "w", encoding="utf-8") as handle:
        json.dump(stage, handle)
    complete = run([sys.executable, PANEL_LIB, "status", evidence])
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
    with open(os.path.join(evidence, "journey.log"), "w", encoding="utf-8") as handle:
        handle.write("recording: 12.0s, 12s of captured wall clock, 123 bytes\n")
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

    # The reviewer answers with a turn_end text content element. A stub `pi` on PATH
    # keeps this offline and deterministic while exercising the real panel stages.
    answer = {"lens": "rams", "verdict": "sound", "summary": "quiet and ordered",
              "findings": []}
    bindir = os.path.join(workdir, "bin")
    os.makedirs(bindir)
    stub = os.path.join(bindir, "pi")
    record = json.dumps({"type": "turn_end", "message": {
        "stopReason": "stop", "content": [{"type": "text", "text": json.dumps(answer)}]}})
    with open(stub, "w", encoding="utf-8") as handle:
        handle.write("#!/bin/bash\nprintf '%s\\n' " + json.dumps(record) + "\n")
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
    need(filled.get("clip_reviews"), "the flagged clip review recorded no verdict")
    need(filled.get("vision_checks"), "the vision checker recorded no verdict")
    status = run([sys.executable, PANEL_LIB, "status", evidence])
    fields = dict(line.split("=", 1) for line in status.stdout.splitlines() if "=" in line)
    need(fields.get("lenses_complete") == "6",
         f"a fully answered panel reported {fields.get('lenses_complete')} completed lenses")
    need("reason=" not in status.stdout, "a fully answered panel still reported a blocking reason")


CHECKS = [
    ("panel answer parser reads the text content element", check_answer_parser),
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
