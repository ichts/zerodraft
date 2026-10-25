#!/bin/bash
# [INPUT] <evidence-dir> from scripts/vm-journey.sh. Env: WID_PANEL_MODEL (default
#         anthropic/claude-opus-5-5), WID_PANEL_ALTERNATES (comma separated
#         fallbacks across families, because a rate-limited or unreachable family
#         must not silently cost a lens), WID_PANEL_LENSES (default the six lenses), WID_PANEL_ATTEMPTS
#         and WID_PANEL_BACKOFF for rate-limited model calls, WID_PANEL_SKIP_MODELS=1
#         to produce the deterministic report without model stages.
# [OUTPUT] <evidence-dir>/panel/: report.html (static, self-contained), panel.json,
#          per-stage answers, the exact command of every model call, and thumbnails.
#          Exit 0 when every stage is complete or its gap is declared; exit 2 on a
#          usage error.
# [POS] apps/macos/FirstLine/scripts/design-panel.sh - the review stage that runs on
#       a recorded acceptance bundle: deterministic findings first, then short clips
#       for the flagged windows, then one design review per lens.
# [PROTOCOL] The deterministic analysis (scripts/vm/analyse-recording.py) is the
#            assertion source and runs before any model. Models only read captures:
#            they never choose an action and never gate a run. A model route that is
#            unavailable is recorded as a declared gap with its exact error, never
#            skipped silently, and never turns into a failure of the recording.
set -uo pipefail

evidence="${1:?usage: design-panel.sh <evidence-dir>}"
evidence="$(cd "$evidence" && pwd -P)"
here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/../../../.." && pwd -P)"
model="${WID_PANEL_MODEL:-anthropic/claude-opus-5-5}"
alternates="${WID_PANEL_ALTERNATES:-anthropic/claude-opus-4-8,anthropic/claude-haiku-5-5,anthropic/claude-fable-5,openai-codex/gpt-5.5,openai-codex/gpt-6-astra,openai/gpt-4o,openai/gpt-5.1}"
lenses="${WID_PANEL_LENSES:-rams norman spiekermann kare matas vignelli}"
attempts="${WID_PANEL_ATTEMPTS:-4}"
backoff="${WID_PANEL_BACKOFF:-30}"
skip_models="${WID_PANEL_SKIP_MODELS:-0}"
panel="$evidence/panel"
answers="$panel/answers"
mkdir -p "$answers" "$panel/thumbs"
rm -f "$panel"/stage-*.json

note() { printf 'design-panel: %s\n' "$*"; }

# --- recorded run metadata -------------------------------------------------------
verdict="$(sed -n 's/^verdict: //p' "$evidence/acceptance.txt" 2>/dev/null)"
artifact="$(sed -n 's/^artifact: //p' "$evidence/acceptance.txt" 2>/dev/null)"
artifact_sha="$(sed -n 's/^artifact_sha256: //p' "$evidence/acceptance.txt" 2>/dev/null)"
recording="$(sed -n 's/^recording: //p' "$evidence/journey.log" 2>/dev/null | tail -1)"
[[ -n "$recording" ]] || recording="no recording line"
python3 - "$panel/stage-00-run.json" "$(basename "$evidence")" "$artifact" "$artifact_sha" "$verdict" "$recording" <<'PY'
import json, sys
out, run, artifact, sha, verdict, recording = sys.argv[1:7]
json.dump({"run": {"run": run, "artifact": artifact, "artifact_sha256": sha,
                   "verdict": verdict or "unknown", "recording": recording}},
          open(out, "w"), indent=2, sort_keys=True)
PY

# --- thumbnails for the step captures -------------------------------------------
make_thumb() { # make_thumb <png> <name>
  sips -s format jpeg -Z 900 "$1" --out "$panel/thumbs/$2" >/dev/null 2>&1
}
step_names=()
if [[ -f "$evidence/steps.tsv" ]]; then
  while IFS=$'\t' read -r _stamp step_path; do
    [[ -n "$step_path" ]] || continue
    base="$(basename "$step_path")"
    step_names+=("$base")
    [[ -f "$evidence/$base.png" ]] && make_thumb "$evidence/$base.png" "$base.jpg"
  done <"$evidence/steps.tsv"
fi
note "step captures: ${#step_names[@]}"

# --- model availability ---------------------------------------------------------
# Verify the reviewer actually answers before any stage depends on it. Every attempt
# is one real call, and the exact command is written into the bundle.
review_model=''
model_notes=()
probe_log="$panel/model-probes.tsv"
: >"$probe_log"
probe_model() { # probe_model <model>
  local candidate="$1" out attempt=1 delay="$backoff"
  out="$answers/probe-$(printf '%s' "$1" | tr '/.' '--').jsonl"
  while [[ "$attempt" -le "$attempts" ]]; do
    pi --model "$candidate" --print --no-session --no-tools --mode json 'Reply with exactly: OK' >"$out" 2>&1
    if grep -q '"type":"turn_end"' "$out" 2>/dev/null \
      && grep '^{' "$out" | jq -e 'select(.type=="turn_end") | (.message.stopReason // "") == "stop"' >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
    if grep -q 'rate_limit_error' "$out" 2>/dev/null; then
      printf '%s\t%s\tsoft\n' "$candidate" "rate limited (advance=rate_limit_error)" >>"$probe_log"
      sleep "$delay"
      delay=$((delay * 2))
      attempt=$((attempt + 1))
      continue
    fi
    printf '%s\t%s\tno\n' "$candidate" "$(grep '^{' "$out" | jq -r 'select(.type=="message_end") | .message.errorMessage // empty' | head -1)" >>"$probe_log"
    return 1
  done
  printf '%s\t%s\tno\n' "$candidate" "gave up after $attempts attempts" >>"$probe_log"
  return 1
}

if [[ "$skip_models" != '1' ]]; then
  review_model="$(probe_model "$model")"
  if [[ -z "$review_model" ]]; then
    IFS=',' read -r -a fallback_list <<<"$alternates"
    for candidate in "${fallback_list[@]}"; do
      [[ -n "$candidate" ]] || continue
      review_model="$(probe_model "$candidate")"
      [[ -n "$review_model" ]] && break
    done
  fi
fi
if [[ -n "$review_model" ]]; then
  note "reviewer model: $review_model"
else
  note "reviewer model unavailable; model stages will be recorded as declared gaps"
fi

# --- deterministic findings -----------------------------------------------------
if [[ -f "$evidence/findings.json" ]]; then
  python3 - "$evidence/findings.json" "$panel/stage-01-findings.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
json.dump({"findings": data.get("findings", []),
           "recording_analysis": data.get("recording", {})}, open(sys.argv[2], "w"),
          indent=2, sort_keys=True)
PY
else
  note 'no findings.json in the bundle: the deterministic analysis did not run for this evidence'
  printf '{"findings": [], "recording_analysis": {"error": "findings.json missing"}}\n' >"$panel/stage-01-findings.json"
fi

# --- flagged clips --------------------------------------------------------------
# Only the flagged windows are reviewed, never the whole recording: the clip covers
# the window plus a second either side, sampled at the recorder's own frame rate
# (the recording is a timestamped frame stream, so there is no finer information).
rec_start="$(cut -f1 "$evidence/recording-span.tsv" 2>/dev/null)"
clip_count=0
clip_reviews='[]'
# The clips are cut for the deterministic findings whether or not a model is
# available: they are evidence in their own right, and the review only adds a verdict.
if [[ -f "$evidence/screen.mov" && -n "$rec_start" && -f "$evidence/findings.json" ]]; then
  flagged=()
  while IFS= read -r flagged_line; do
    [[ -n "$flagged_line" ]] && flagged+=("$flagged_line")
  done < <(jq -r '[.findings[] | select(.t_start != null)]
    | sort_by((if .severity == "high" then 0 elif .severity == "low" then 2 else 1 end), .t_start)
    | .[0:6][] | "\(.t_start)\t\(.t_end)\t\(.kind)\t\(.note)"' "$evidence/findings.json" 2>/dev/null)
  for entry in ${flagged[@]+"${flagged[@]}"}; do
    IFS=$'\t' read -r t_start t_end kind finding_note <<<"$entry"
    rel_start=$(( (t_start - rec_start) / 1000 - 1 ))
    [[ "$rel_start" -lt 0 ]] && rel_start=0
    clip_count=$((clip_count + 1))
    # Raised rate: resample the window to 10 fps, then keep six frames spread across
    # it, so a sub-second state has a chance to appear in the review set.
    rm -f "$panel"/clip-"$clip_count"-*.png
    ffmpeg -loglevel error -ss "$rel_start" -i "$evidence/screen.mov" -vf "fps=10" \
      -frames:v 60 "$panel/clip-$clip_count-%03d.png" -y >/dev/null 2>&1
    available=$(ls "$panel"/clip-"$clip_count"-*.png 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${available:-0}" -gt 0 ]]; then
      for slot in 0 1 2 3 4 5; do
        source_index=$(( 1 + slot * available / 6 ))
        source_file=$(printf '%s/clip-%s-%03d.png' "$panel" "$clip_count" "$source_index")
        [[ -f "$source_file" ]] && make_thumb "$source_file" "frame-$t_start-$slot.jpg"
      done
    fi
    if [[ -z "$review_model" ]]; then
      note "clip $clip_count: frames cut for the record; no reviewer model answered, so no verdict"
      continue
    fi
    prompt="$panel/clip-$clip_count-prompt.txt"
    cat >"$prompt" <<EOF
You are reviewing a flagged window from a recorded macOS acceptance run of the app
"Write It Down" (a forced-output writing tool). A deterministic analysis flagged this
window; decide whether it shows a real interface defect or expected behaviour.

Flagged window: ${t_start} ms to ${t_end} ms (${kind}). Analyst note: ${finding_note}

Read these frames in order (they are consecutive captures around the flag):
$(for slot in 0 1 2 3 4 5; do [[ -f "$panel/thumbs/frame-$t_start-$slot.jpg" ]] && printf -- '- %s/thumbs/frame-%s-%s.jpg\n' "$panel" "$t_start" "$slot"; done)

Answer with one JSON object and nothing else:
{"verdict": "defect" | "expected", "severity": "blocker" | "major" | "minor" | "nit",
 "reason": "one paragraph naming what changed between the frames",
 "what_to_fix": "one sentence, or empty when the verdict is expected"}
EOF
    answer_file="$answers/clip-$clip_count.jsonl"
    command_line="pi --model $review_model --print --no-session --tools read --mode json \"\$(cat $prompt)\""
    pi --model "$review_model" --print --no-session --tools read --mode json "$(cat "$prompt")" >"$answer_file" 2>&1
    text="$(grep '^{' "$answer_file" | jq -r 'select(.type=="turn_end") | .message.content[]? | select(.type=="text") | .text' | tail -1)"
    parsed="$(printf '%s' "$text" | python3 "$here/vm/panel-lib.py" extract 2>/dev/null)"
    if [[ -z "$parsed" ]]; then
      note "clip $clip_count: the reviewer did not return JSON"
      continue
    fi
    frames_json="$(for slot in 0 1 2 3 4 5; do [[ -f "$panel/thumbs/frame-$t_start-$slot.jpg" ]] && printf 'frame-%s-%s.jpg\n' "$t_start" "$slot"; done | jq -R . | jq -sc .)"
    clip_reviews="$(jq -c --arg window "$t_start-$t_end" --arg model "$review_model" \
      --arg command "$command_line" --argjson frames "$frames_json" --argjson answer "$parsed" \
      '. + [{window: $window, model: $model, command: $command, frames: $frames} + $answer]' <<<"$clip_reviews")"
  done
fi
jq -n --argjson reviews "$clip_reviews" '{clip_reviews: $reviews}' >"$panel/stage-02-clips.json"
note "flagged clips reviewed: $clip_count"

# --- vision checker -------------------------------------------------------------
# After a step that changes the screen, ask whether the scripted next step still
# makes sense on that new screen, and record which step index needs a visual check.
vision='[]'
if [[ "$skip_models" != '1' && -n "$review_model" && ${#step_names[@]} -gt 1 ]]; then
  for ((i = 0; i + 1 < ${#step_names[@]}; i++)); do
    before="$evidence/${step_names[i]}.png"
    after="$evidence/${step_names[i + 1]}.png"
    next="$(printf '%s' "${step_names[i + 1]}")"
    [[ -f "$before" && -f "$after" ]] || continue
    metric="$(ffmpeg -hide_banner -i "$before" -i "$after" -lavfi '[0:v][1:v]psnr' -f null - 2>&1 \
      | grep -o 'average:[0-9.]*' | head -1 | cut -d: -f2)"
    [[ "$metric" == 'inf' ]] && continue
    if ! awk -v m="${metric:-0}" 'BEGIN { exit !(m < 34) }'; then continue; fi
    make_thumb "$before" "vision-before-$i.jpg"
    make_thumb "$after" "vision-after-$i.jpg"
    prompt="$panel/vision-$i-prompt.txt"
    cat >"$prompt" <<EOF
A scripted acceptance run steps through the "Write It Down" macOS app and takes a
screenshot at each step. Two consecutive steps changed the screen noticeably.

Before (step ${i}: ${step_names[i]}): $before
After (step $((i + 1)): ${step_names[i + 1]}): $after
The scripted next action after that point is step $((i + 2)) of the script: $(printf '%s' "${step_names[i + 2]:-end of script}").

Read both images, then answer with one JSON object and nothing else:
{"next_step_valid": true | false,
 "check_step_index": <index of the next step that needs a human visual check>,
 "reason": "one paragraph tying the visible screen to that step"}
EOF
    answer_file="$answers/vision-$i.jsonl"
    command_line="pi --model $review_model --print --no-session --tools read --mode json \"\$(cat $prompt)\""
    pi --model "$review_model" --print --no-session --tools read --mode json "$(cat "$prompt")" >"$answer_file" 2>&1
    text="$(grep '^{' "$answer_file" | jq -r 'select(.type=="turn_end") | .message.content[]? | select(type=="text") | .text' | tail -1)"
    parsed="$(printf '%s' "$text" | python3 "$here/vm/panel-lib.py" extract 2>/dev/null)"
    [[ -z "$parsed" ]] && { note "vision check $i: no JSON answer"; continue; }
    vision="$(jq -c --arg transition "${step_names[i]} -> ${step_names[i+1]}" --arg next "$next" \
      --argjson answer "$parsed" '. + [{transition: $transition, next_step: $next} + $answer]' <<<"$vision")"
  done
fi
jq -n --argjson checks "$vision" '{vision_checks: $checks}' >"$panel/stage-03-vision.json"
note "vision checks: $(jq 'length' <<<"$vision")"

# --- six lenses -----------------------------------------------------------------
# Each lens reads the product's own quality records before it looks at a capture.
documents=("docs/ui-quality.md" "docs/wid-decisions.md" "design/DESIGN.md")
available_documents=()
for document in "${documents[@]}"; do
  [[ -f "$repo/$document" ]] && available_documents+=("$repo/$document")
done
captures=()
for name in "${step_names[@]}"; do
  [[ -f "$evidence/$name.png" ]] && captures+=("$evidence/$name.png")
done

lens_brief() { # lens_brief <lens>
  case "$1" in
    rams) printf 'Dieter Rams: as little design as possible. Judge whether anything on screen is decoration that carries no function, whether the surfaces are quiet and ordered, and whether the same object is presented the same way twice.' ;;
    norman) printf 'Don Norman: affordances, mapping, feedback, error recovery. Judge whether a person can tell what to do next, whether every action answers visibly, and whether a blocked or failed action explains itself.' ;;
    spiekermann) printf 'Erik Spiekermann: type as the interface. Judge typographic hierarchy, measure, casing, alignment of labels and numerals, and whether the words say what the thing does.' ;;
    kare) printf 'Susan Kare: the honest pixel. Judge iconography, alignment on the grid, optical centring of marks and numerals, and whether small elements stay legible at real size.' ;;
    matas) printf 'Jony-free but human: judge motion and time. Does anything move without a reason, arrive late, or interrupt the writer; does a change of state read as one event or as several.' ;;
    vignelli) printf 'Massimo Vignelli: the grid and the few right types. Judge the underlying grid, margin consistency, whether the screen obeys one spacing scale, and whether it would survive without decoration.' ;;
    *) printf '%s: review this interface against the product records you read.' "$1" ;;
  esac
}

lens_stage='[]'
for lens in $lenses; do
  if [[ "$skip_models" == '1' || -z "$review_model" ]]; then
    lens_stage="$(jq -c --arg lens "$lens" --arg error "$([[ "$skip_models" == '1' ]] && printf 'model stages disabled by WID_PANEL_SKIP_MODELS=1' || printf '%s' "${model_notes[*]:-no reviewer model answered}")" \
      '. + [{lens: $lens, status: "unavailable", error: $error, command: "not attempted"}]' <<<"$lens_stage")"
    continue
  fi
  prompt="$panel/lens-$lens-prompt.txt"
  {
    printf 'You are %s\n\n' "$(lens_brief "$lens")"
    printf 'Before you look at any capture, read these product records in full, in this order:\n'
    for document in "${available_documents[@]}"; do printf -- '- %s\n' "$document"; done
    printf '\nThen read these screenshots of a recorded acceptance run of the shipped macOS app:\n'
    for capture in "${captures[@]}"; do printf -- '- %s\n' "$capture"; done
    printf '\nStep names in recorded order: %s\n' "${step_names[*]}"
    cat <<'RULES'

Report only what the captures and the records support. Rank by severity. For each
finding, name the screenshot file it comes from, and say whether the captured screen
contradicts a recorded decision or quality rule (quote the rule) or is simply your
judgement. Do not propose product changes outside this app's contract.

Answer with one JSON object and nothing else:
{"lens": "<name>", "verdict": "sound" | "needs work" | "blocked",
 "summary": "two sentences",
 "findings": [{"severity": "blocker" | "major" | "minor" | "nit",
               "title": "short claim",
               "why": "the evidence you saw and the rule it touches",
               "evidence": "<screenshot file>",
               "fix": "the smallest change that removes the finding"}]}
RULES
  } >"$prompt"
  answer_file="$answers/lens-$lens.jsonl"
  command_line="pi --model $review_model --print --no-session --tools read --mode json \"\$(cat $prompt)\""
  pi --model "$review_model" --print --no-session --tools read --mode json "$(cat "$prompt")" >"$answer_file" 2>&1
  text="$(grep '^{' "$answer_file" | jq -r 'select(.type=="turn_end") | .message.content[]? | select(type=="text") | .text' | tail -1)"
  parsed="$(printf '%s' "$text" | python3 "$here/vm/panel-lib.py" extract 2>/dev/null)"
  if [[ -z "$parsed" ]]; then
    reason="$(grep '^{' "$answer_file" | jq -r 'select(.type=="message_end") | .message.errorMessage // empty' | head -1)"
    lens_stage="$(jq -c --arg lens "$lens" --arg error "${reason:-no JSON answer}" --arg command "$command_line" \
      '. + [{lens: $lens, status: "unavailable", error: $error, command: $command}]' <<<"$lens_stage")"
    note "lens $lens: no answer (${reason:-no JSON})"
    continue
  fi
  lens_stage="$(jq -c --arg lens "$lens" --arg model "$review_model" --arg command "$command_line" --argjson answer "$parsed" \
    '. + [{lens: $lens, status: "complete", model: $model, command: $command, answer: $answer}]' <<<"$lens_stage")"
  note "lens $lens: complete"
done
jq -n --argjson lenses "$lens_stage" '{lenses: $lenses}' >"$panel/stage-04-lenses.json"

# --- capability matrix and declared gaps ----------------------------------------
gaps=()
capabilities='[]'
capabilities="$(jq -c --arg model "$review_model" \
  '. + [{stage: "reviewer model", status: ($model | if . == "" then "declared gap" else "complete" end), model: $model, detail: (if $model == "" then "no candidate route answered; see panel/model-probes.tsv" else "answered the readiness probe" end)}]' <<<"$capabilities")"
while IFS=$'\t' read -r probed_model probed_detail _probed_soft; do
  [[ -n "${probed_model:-}" ]] || continue
  capabilities="$(jq -c --arg model "$probed_model" --arg detail "$probed_detail" \
    '. + [{stage: "reviewer candidate", status: "declared gap", route: $model, detail: $detail}]' <<<"$capabilities")"
done <"$probe_log"
capabilities="$(jq -c '. + [{stage: "deterministic analysis", status: "complete", model: "", detail: "scripts/vm/analyse-recording.py, no model"}]' <<<"$capabilities")"
for route in cursor/gemini-3.8-flash cursor/gemini-4-argon; do
  probe_out="$answers/probe-$(printf '%s' "$route" | tr '/' '-').jsonl"
  pi --model "$route" --print --no-session --no-tools --mode json 'Reply with exactly: OK' >"$probe_out" 2>&1
  detail="$(grep '^{' "$probe_out" | jq -r 'select(.type=="message_end") | .message.errorMessage // empty' | head -1)"
  if [[ -z "$detail" ]] && grep -q '"type":"turn_end"' "$probe_out" 2>/dev/null; then
    capabilities="$(jq -c --arg route "$route" '. + [{stage: "gemini review route", status: "complete", route: $route, detail: "answered"}]' <<<"$capabilities")"
  else
    capabilities="$(jq -c --arg route "$route" --arg detail "${detail:-no answer}" \
      '. + [{stage: "gemini review route", status: "declared gap", route: $route, detail: $detail}]' <<<"$capabilities")"
    gaps+=("Gemini route $route is unavailable on this machine: ${detail:-no answer}. Flagged clips were reviewed by $([[ -n "$review_model" ]] && printf '%s' "$review_model" || printf 'no model') instead.")
  fi
done
if [[ -z "$review_model" ]]; then
  gaps+=("No reviewer model answered from this lane. Every candidate is listed with its exact error in panel/model-probes.tsv and in the capability matrix; the deterministic analysis and the report were still produced. Re-run: bash apps/macos/FirstLine/scripts/design-panel.sh $(printf '%s' "$evidence")")
fi
[[ "$skip_models" == '1' ]] && gaps+=("Model stages were disabled by WID_PANEL_SKIP_MODELS=1; only the deterministic analysis ran.")
jq -n --argjson capabilities "$capabilities" --argjson gaps "$(printf '%s\n' "${gaps[@]:-}" | jq -R . | jq -sc '[.[] | select(. != "")]')" \
  '{capabilities: $capabilities, declared_gaps: $gaps}' >"$panel/stage-05-capabilities.json"

# --- assemble and render ---------------------------------------------------------
python3 - "$panel" <<'PY'
import json, glob, sys, os
panel = sys.argv[1]
merged = {}
for path in sorted(glob.glob(os.path.join(panel, "stage-*.json"))):
    with open(path, encoding="utf-8") as handle:
        for key, value in json.load(handle).items():
            if isinstance(value, list) and isinstance(merged.get(key), list):
                merged[key].extend(value)
            else:
                merged[key] = value
with open(os.path.join(panel, "panel.json"), "w", encoding="utf-8") as handle:
    json.dump(merged, handle, indent=2, sort_keys=True)
print("panel.json written")
PY
report="$(python3 "$here/vm/panel-lib.py" report "$evidence")"
note "report: $report"
if [[ "${#gaps[@]}" -gt 0 ]]; then
  for gap in "${gaps[@]}"; do note "declared gap: $gap"; done
fi
note "deterministic findings: $(jq 'length' <<<"$(jq -c '.findings' "$panel/stage-01-findings.json")")"
exit 0
