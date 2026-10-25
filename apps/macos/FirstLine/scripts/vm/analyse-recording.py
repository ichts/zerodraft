#!/usr/bin/env python3
"""Deterministic analysis of a recorded acceptance run.

[INPUT] <evidence-dir> containing frames.tsv (wall clock per captured frame), the
        frames/ directory the recorder wrote, steps.tsv (the rig's own recorded
        steps) and the launch watcher streams launch-*.jsonl.
[OUTPUT] findings.json (structured findings), frame-deltas.tsv (per-frame mean
         absolute difference and global SSIM against the previous frame, with the
         wall clock), and PASS/FAIL assertion lines on stdout so the host verdict
         counts them like any other assertion. Findings carry a kind, a severity, a
         wall-clock window, the frame indices and the text that triggered them.
[POS] apps/macos/FirstLine/scripts/vm/analyse-recording.py - the model-free
      detector that runs on every recording. It is the assertion source: it can
      fail a run on a gapped, frozen or truncated recording and on a transient UI
      state during launch, which is the class of defect the 1.0 launch finding
      proved exists. Model review reads its findings; it never replaces them.
[PROTOCOL] Deterministic only: no model decides here. A detector fails the run
           only when the signal is unambiguous (a capture gap, a frozen screen for
           most of a minute, a forbidden surface that appears and vanishes during
           launch); everything else is recorded as an informational finding for the
           review stage. Thresholds are named constants, not magic numbers.
"""

import json
import os
import re
import subprocess
import sys

# A capture gap this long means the recorder stopped covering the run.
MAX_FRAME_GAP_MS = 2000
# A screen that does not change at all for this long, with no recorded step inside
# the window, is a frozen screen: the app hung or the capture stalled.
FROZEN_MEAN_DELTA = 0.6
FROZEN_ASSERT_MS = 20000
FROZEN_NOTE_MS = 4000
# A change this large after a settled run is a candidate flash or jump.
SPIKE_MIN_MEAN_DELTA = 8.0
SPIKE_MEDIAN_FACTOR = 6.0
# Structural similarity (global, luminance only) between consecutive frames. A dip
# below the first value is a real change of content rather than a caret or a fade;
# a dip that recovers above the second value within FLASH_MAX_FRAMES is a transient
# state a person would read as a flash.
SSIM_CHANGE = 0.90
SSIM_STABLE = 0.98
FLASH_MAX_FRAMES = 3
# A launch state that lives at most this long and is replaced by another state is a
# transient: it is what a person sees as a flash.
TRANSIENT_MAX_MS = 3000
# The assertion id a declared known defect may excuse. It belongs to the licensed
# relaunch streams; the same surface anywhere else fails under its own id.
DECLARED_LAUNCH_ASSERTION = "licensed-launch-no-activation-page"
# Surfaces that must never appear during the launch of a licensed install.
FORBIDDEN_LAUNCH_TEXT = [
    (re.compile(r"Activate Write It Down", re.I), DECLARED_LAUNCH_ASSERTION),
    (re.compile(r"Enter your order number", re.I), DECLARED_LAUNCH_ASSERTION),
    (re.compile(r"License not activated on this Mac", re.I), DECLARED_LAUNCH_ASSERTION),
]
# Every frame is scaled to this width before differencing, so the metric is cheap
# and comparable between runs (a full-size difference would be dominated by noise).
DIFF_WIDTH = 192

log = []


def say(message):
    log.append(message)
    print(message, flush=True)


def read_manifest(path):
    frames = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            stamp, name = line.split("\t", 1)
            frames.append((int(stamp), name))
    return frames


def read_steps(path):
    steps = []
    if not os.path.exists(path):
        return steps
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            stamp, name = line.split("\t", 1)
            steps.append((stamp, name))
    return steps


def frame_size(evidence, frames):
    """Bytes per decoded grayscale frame, measured on the first captured frame."""
    first = os.path.join(evidence, "frames", frames[0][1])
    if not os.path.exists(first):
        raise RuntimeError(f"the first captured frame {frames[0][1]!r} is missing from frames/")
    result = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-nostdin", "-i", first,
         "-vf", f"scale={DIFF_WIDTH}:-1,format=gray", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
        capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"ffmpeg could not decode the first frame: {result.stderr[:400]!r}")
    if not result.stdout:
        raise RuntimeError("the first captured frame decoded to nothing")
    return len(result.stdout)


def frame_deltas(evidence, frames):
    """Mean absolute luminance difference between each frame and the previous one."""
    if len(frames) < 2:
        return []
    per_frame = frame_size(evidence, frames)
    pattern = os.path.join(evidence, "frames", "%06d.jpg")
    command = [
        "ffmpeg", "-loglevel", "error", "-nostdin", "-start_number", "0",
        "-i", pattern, "-vf", f"scale={DIFF_WIDTH}:-1,format=gray",
        "-f", "rawvideo", "-pix_fmt", "gray", "-",
    ]
    result = subprocess.run(command, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg could not decode the frame stream: {result.stderr[:400]!r}")
    raw = result.stdout
    decoded = len(raw) // per_frame
    if len(raw) % per_frame:
        raise RuntimeError(
            f"the frame stream decoded to a trailing {len(raw) % per_frame}-byte partial image; "
            "it is not the recorder's frame sequence")
    if decoded != len(frames):
        raise RuntimeError(
            f"the frame stream decoded to {decoded} images for {len(frames)} recorded frames: "
            "a capture is missing, so every per-frame metric would be misaligned")
    deltas = []
    similarities = []
    previous = raw[0:per_frame]
    for index in range(1, len(frames)):
        current = raw[index * per_frame:(index + 1) * per_frame]
        if len(current) != per_frame:
            break
        total = 0
        for left, right in zip(previous, current):
            delta = left - right
            total += delta if delta >= 0 else -delta
        deltas.append(total / per_frame)
        similarities.append(ssim(previous, current))
        previous = current
    return deltas, similarities


def ssim(previous, current):
    """Global SSIM of two equal-length 8-bit grayscale buffers (luminance only)."""
    count = len(previous)
    if not count or len(current) != count:
        return 1.0
    sum_x = sum(previous)
    sum_y = sum(current)
    sum_xx = sum(value * value for value in previous)
    sum_yy = sum(value * value for value in current)
    sum_xy = sum(left * right for left, right in zip(previous, current))
    mean_x = sum_x / count
    mean_y = sum_y / count
    var_x = sum_xx / count - mean_x * mean_x
    var_y = sum_yy / count - mean_y * mean_y
    cov = sum_xy / count - mean_x * mean_y
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    denominator = (mean_x ** 2 + mean_y ** 2 + c1) * (var_x + var_y + c2)
    if denominator == 0:
        return 1.0
    return ((2 * mean_x * mean_y + c1) * (2 * cov + c2)) / denominator


def median(values):
    ordered = sorted(values)
    if not ordered:
        return 0.0
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def step_in_window(steps, start_ms, end_ms):
    for stamp, _ in steps:
        moment = stamp_ms(stamp)
        if start_ms - 1500 <= moment <= end_ms + 1500:
            return True
    return False


def stamp_ms(iso_stamp):
    """steps.tsv carries UTC ISO seconds; convert to epoch milliseconds."""
    from datetime import datetime, timezone
    return int(datetime.strptime(iso_stamp, "%Y-%m-%dT%H:%M:%SZ")
               .replace(tzinfo=timezone.utc).timestamp() * 1000)


def video_findings(frames, deltas, similarities, steps):
    findings = []
    # 1. capture gaps
    for index in range(1, len(frames)):
        gap = frames[index][0] - frames[index - 1][0]
        if gap > MAX_FRAME_GAP_MS:
            findings.append({
                "kind": "capture-gap",
                "severity": "high",
                "assertion": "recording-gap",
                "t_start": frames[index - 1][0],
                "t_end": frames[index][0],
                "duration_ms": gap,
                "frames": [index - 1, index],
                "note": f"no frame captured for {gap} ms; the recording does not cover that window",
            })
    # 2. frozen screen
    run_start = None
    for index, delta in enumerate(deltas):
        start_ms = frames[index][0]
        end_ms = frames[index + 1][0]
        frozen = delta < FROZEN_MEAN_DELTA
        if frozen and run_start is None:
            run_start = index
        if not frozen and run_start is not None:
            findings.extend(frozen_window(frames, steps, run_start, index))
            run_start = None
    if run_start is not None:
        findings.extend(frozen_window(frames, steps, run_start, len(deltas)))
    # 3. transient structural states: content changes and then comes back
    for index, value in enumerate(similarities):
        if value >= SSIM_CHANGE:
            continue
        for probe in range(index + 1, min(index + FLASH_MAX_FRAMES + 1, len(similarities))):
            if similarities[probe] > SSIM_STABLE:
                start_ms = frames[index][0]
                end_ms = frames[probe + 1][0]
                findings.append({
                    "kind": "transient-screen-state",
                    "severity": "low",
                    "assertion": None,
                    "t_start": start_ms,
                    "t_end": end_ms,
                    "duration_ms": end_ms - start_ms,
                    "frames": [index, probe + 1],
                    "ssim": round(value, 3),
                    "note": ("the screen changed structurally for %.0f ms and then returned to "
                             "the previous content" % (end_ms - start_ms)),
                })
                break
    # 4. spikes: a large change after a settled stretch is a flash or a hard cut
    baseline = median(deltas) or 1.0
    threshold = max(SPIKE_MIN_MEAN_DELTA, baseline * SPIKE_MEDIAN_FACTOR)
    for index, delta in enumerate(deltas):
        if delta < threshold:
            continue
        window_start = frames[index][0]
        window_end = frames[min(index + 2, len(frames) - 1)][0]
        explained = step_in_window(steps, window_start, window_end)
        findings.append({
            "kind": "screen-change",
            "severity": "info" if explained else "low",
            "assertion": None,
            "t_start": window_start,
            "t_end": window_end,
            "duration_ms": window_end - window_start,
            "frames": [index, min(index + 1, len(frames) - 1)],
            "mean_delta": round(delta, 2),
            "ssim": round(similarities[index], 3),
            "note": ("a recorded step covers this change" if explained
                     else "a full-screen change with no recorded step nearby"),
        })
    return findings


def frozen_window(frames, steps, start_index, end_index):
    start_ms = frames[start_index][0]
    end_ms = frames[end_index][0]
    span = end_ms - start_ms
    if span < FROZEN_NOTE_MS:
        return []
    covered = step_in_window(steps, start_ms, end_ms)
    severity = "info"
    assertion = None
    if span >= FROZEN_ASSERT_MS and not covered:
        severity = "high"
        assertion = "recording-stall"
    return [{
        "kind": "frozen-screen",
        "severity": severity,
        "assertion": assertion,
        "t_start": start_ms,
        "t_end": end_ms,
        "duration_ms": span,
        "frames": [start_index, end_index],
        "note": ("the screen did not change at all for %.1f s%s" % (
            span / 1000, "; a recorded step covers it" if covered else "")),
    }]


def launch_assertion_id(stream_name):
    """Key the launch assertion to the stream it was seen in.

    Only a licensed relaunch carries the id a declared known defect may excuse; the
    same surface in any other launch stream is still a defect, under its own id, so
    the declaration cannot excuse it.
    """
    if stream_name.startswith("launch-licensed-"):
        return DECLARED_LAUNCH_ASSERTION
    return f"{stream_name[:-len('.jsonl')]}-no-activation-page"


def launch_findings(evidence, steps):
    findings = []
    for name in sorted(os.listdir(evidence)):
        if not (name.startswith("launch-") and name.endswith(".jsonl")):
            continue
        states = []
        with open(os.path.join(evidence, name), encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                text = record.get("text") or ""
                moment = int(record.get("t", 0) * 1000)
                if states and states[-1][1] == text:
                    continue
                states.append((moment, text))
        for index, (moment, text) in enumerate(states):
            end = states[index + 1][0] if index + 1 < len(states) else moment
            lived = end - moment
            if not text or index == len(states) - 1:
                continue
            if lived > TRANSIENT_MAX_MS:
                continue
            forbidden = [(pattern, launch_assertion_id(name))
                         for pattern, assertion in FORBIDDEN_LAUNCH_TEXT
                         if pattern.search(text)]
            findings.append({
                "kind": "transient-launch-state",
                "severity": "high" if forbidden else "low",
                "assertion": forbidden[0][1] if forbidden else None,
                "t_start": moment,
                "t_end": end,
                "duration_ms": lived,
                "frames": [],
                "source": name,
                "text": text[:240],
                "note": ("a forbidden surface appeared for %d ms during launch" % lived
                         if forbidden else
                         "a launch state appeared for %d ms before the settled surface" % lived),
            })
    return findings


def main(argv):
    if len(argv) != 2:
        print("usage: analyse-recording.py <evidence-dir>", file=sys.stderr)
        return 2
    evidence = os.path.abspath(argv[1])
    manifest = os.path.join(evidence, "frames.tsv")
    if not os.path.exists(manifest):
        say("FAIL [recording-analysis] the evidence bundle has no frame stream to analyse")
        return 1
    frames = read_manifest(manifest)
    steps = read_steps(os.path.join(evidence, "steps.tsv"))

    findings = []
    deltas = []
    similarities = []
    analysis_error = None
    try:
        deltas, similarities = frame_deltas(evidence, frames)
    except RuntimeError as error:
        analysis_error = str(error)
    if deltas:
        findings.extend(video_findings(frames, deltas, similarities, steps))
    findings.extend(launch_findings(evidence, steps))
    launch_assertions = sorted({
        launch_assertion_id(name)
        for name in os.listdir(evidence)
        if name.startswith("launch-") and name.endswith(".jsonl")})
    # One finding per distinct window and kind: the detectors can hit the same window
    # from two directions (a dip and its recovery), which is noise for a reviewer.
    seen = set()
    unique = []
    for finding in findings:
        key = (finding["kind"], finding.get("t_start"), finding.get("t_end"), finding.get("assertion"))
        if key in seen:
            continue
        seen.add(key)
        unique.append(finding)
    findings = unique

    span = (frames[-1][0] - frames[0][0]) if frames else 0
    summary = {
        "frames": len(frames),
        "span_ms": span,
        "median_frame_delta": round(median(deltas), 3) if deltas else None,
        "max_frame_delta": round(max(deltas), 3) if deltas else None,
        "median_ssim": round(median(similarities), 4) if similarities else None,
        "min_ssim": round(min(similarities), 4) if similarities else None,
        "diff_width": DIFF_WIDTH,
        "thresholds": {
            "max_frame_gap_ms": MAX_FRAME_GAP_MS,
            "frozen_mean_delta": FROZEN_MEAN_DELTA,
            "frozen_assert_ms": FROZEN_ASSERT_MS,
            "spike_min_mean_delta": SPIKE_MIN_MEAN_DELTA,
            "transient_max_ms": TRANSIENT_MAX_MS,
            "ssim_change": SSIM_CHANGE,
            "ssim_stable": SSIM_STABLE,
        },
    }
    if analysis_error:
        summary["error"] = analysis_error

    with open(os.path.join(evidence, "findings.json"), "w", encoding="utf-8") as handle:
        json.dump({"recording": summary, "findings": findings}, handle, indent=2, sort_keys=True)

    # Trailing per-frame metric, so a reviewer can re-derive any finding.
    if deltas:
        with open(os.path.join(evidence, "frame-deltas.tsv"), "w", encoding="utf-8") as handle:
            handle.write("frame\twall_ms\tmean_delta\tssim\n")
            for index, delta in enumerate(deltas):
                handle.write("%d\t%d\t%.3f\t%.4f\n" % (
                    index + 1, frames[index + 1][0], delta, similarities[index]))

    if analysis_error:
        say(f"FAIL [recording-analysis] {analysis_error}")
        return 1

    say("PASS [recording-analysis] analysed %d frames over %.1f s, frame differencing and global SSIM "
        "on every captured frame (median delta %.2f, max %.2f, min SSIM %.3f)"
        % (len(frames), span / 1000, summary["median_frame_delta"] or 0.0,
           summary["max_frame_delta"] or 0.0, summary["min_ssim"] or 1.0))

    failed_ids = []
    for finding in findings:
        assertion = finding.get("assertion")
        if not assertion:
            continue
        if assertion in failed_ids:
            continue
        failed_ids.append(assertion)
        say("FAIL [%s] %s (%s, %.0f ms)" % (
            assertion, finding["note"], finding["kind"], finding["duration_ms"]))
    if "recording-gap" not in failed_ids:
        say(f"PASS [recording-gap] every consecutive frame pair is under {MAX_FRAME_GAP_MS} ms apart")
    if "recording-stall" not in failed_ids:
        say(f"PASS [recording-stall] no frozen window of {FROZEN_ASSERT_MS} ms or longer")
    for assertion in launch_assertions:
        if assertion not in failed_ids:
            say(f"PASS [{assertion}] no forbidden surface appeared transiently in its launch stream")
    informational = [finding for finding in findings if not finding.get("assertion")]
    say("findings recorded for review: %d (assertion failures: %d)" % (
        len(findings), len(failed_ids)))
    return 1 if failed_ids else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
