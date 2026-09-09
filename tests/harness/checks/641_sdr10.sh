#!/usr/bin/env bash
# 10-bit SDR format selection.
#   1. umbrielfx rendering: corner_radius + optimized blur active on a live
#      window while the bit-depth switches in both directions. Every frame is
#      lit, shows the configured backdrop, and matches the 8-bit mean colour.
#   2. SDR8 -> SDR10: Probe succeeds, output commits to XR30 or XB30, no fallback reason.
#   3. HDR (unavailable) -> SDR10: HDR reason clears when HDR is no longer
#      requested; SDR10 independently selects XR30 or XB30.
#   4. HDR unavailable + SDR10 configured: The HDR reason stays set while SDR10
#      commits XR30 or XB30 successfully.
#   5. SDR10 -> SDR8: No fallback reason, output returns to XR24.
set -euo pipefail

readonly BASELINE="$(< "$UMBRIEL_CONFIG")"

readonly FX_CONFIG='
[colors]
backdrop = "#1e1e2eff"

[appearance]
corner_radius = 32

[appearance.blur]
enabled = true
optimized = true
passes = 2
radius = 8
noise = 0.0
brightness = 1.0
contrast = 1.0
saturation = 1.0

[[window_rule]]
blur = true'

readonly SDR10_CONFIG='
[output.HEADLESS-1]
bit_depth = 10'

readonly SDR10_ACTIVE='
  .outputs[0].configured_bit_depth == 10
  and .outputs[0].bit_depth_fallback_reason == ""
  and .outputs[0].sdr10_active == true
  and (.outputs[0].render_format == "XR30" or .outputs[0].render_format == "XB30")'

write_config() {
  printf '%s\n%s\n' "$BASELINE" "${1:-}" > "$UMBRIEL_CONFIG"
  "$UMBRIEL" msg config-reload > /dev/null
}

expect_color() {
  local label=$1 filter=$2
  local color
  color=$("$UMBRIEL" color --json)
  if ! jq -e "$filter" <<< "$color" > /dev/null; then
    echo "$label: unexpected color state: $color"
    exit 1
  fi
}

expect_human_sdr10_active() {
  local label=$1
  local color_human
  color_human=$("$UMBRIEL" color)
  if ! grep -F "10-bit SDR: active" <<< "$color_human" > /dev/null; then
    echo "$label: missing 10-bit SDR active line in human output: $color_human"
    exit 1
  fi
}

# The FX_CONFIG backdrop as grim encodes it, sampled inside the outer layout gap.
readonly BACKDROP_RGB=(30 30 46)
readonly BACKDROP_X=2 BACKDROP_Y=2
readonly CHANNEL_TOLERANCE=2
FRAME_MEAN=

# Fails unless each channel of "r g b" in $2 is within $4 of the matching channel in $3.
expect_rgb_near() {
  local label=$1 tolerance=$4
  local -a actual expected
  read -ra actual <<< "$2"
  read -ra expected <<< "$3"
  local i
  for i in 0 1 2; do
    if (( ${actual[i]} - ${expected[i]} > tolerance || ${expected[i]} - ${actual[i]} > tolerance )); then
      echo "phase1: $label: got rgb $2, expected $3 (tolerance $tolerance)"
      exit 1
    fi
  done
}

# Settles, captures the output, and fails if the frame is all black or the
# backdrop in the outer gap is not the configured colour. Leaves the frame's
# mean colour in FRAME_MEAN.
expect_rendered() {
  local label=$1
  local screenshot="$UMBRIEL_RUNTIME_DIR/sdr10-$label.png"
  local lit backdrop
  "$UMBRIEL" settle
  grim "$screenshot"
  lit=$("$UMBRIEL_PIXEL_PROBE" "$screenshot" count 'r > 0 || g > 0 || b > 0')
  if (( lit == 0 )); then
    echo "phase1: $label screenshot is all-black"
    exit 1
  fi
  backdrop=$("$UMBRIEL_PIXEL_PROBE" "$screenshot" pixel "$BACKDROP_X" "$BACKDROP_Y")
  expect_rgb_near "$label backdrop at ${BACKDROP_X},${BACKDROP_Y}" "$backdrop" "${BACKDROP_RGB[*]}" "$CHANNEL_TOLERANCE"
  FRAME_MEAN=$("$UMBRIEL_PIXEL_PROBE" "$screenshot" mean)
  echo "phase1: $label frame rendered with blur/corner_radius active (backdrop=${backdrop}, mean=${FRAME_MEAN})"
}

# -- Phase 1: umbrielfx rendering ---------------------------------------------
# Enable corner_radius and optimized blur on a live window, then switch
# bit_depth in both directions. Each capture must be lit and show the
# configured backdrop in the outer gap, which catches a swapped XR30/XB30
# channel order or a wrong transfer on the 10-bit path. The 10-bit and returning
# 8-bit frames must also match the first 8-bit frame's mean colour, so blur and
# corner_radius output does not shift across the transition. Cache-format
# correctness is verified separately by the umbrielfx unit test
# `color-optimized-blur-format-cache`.
write_config "$FX_CONFIG"

foot --config=/dev/null sh -c 'while :; do sleep 1; done' > /dev/null 2>&1 &
for _ in $(seq 60); do
  [[ $("$UMBRIEL" windows --json | jq 'length') -ge 1 ]] && break
  sleep 0.1
done
if [[ $("$UMBRIEL" windows --json | jq 'length') -lt 1 ]]; then
  echo "phase1: foot window never mapped"
  exit 1
fi

expect_rendered sdr8
readonly SDR8_MEAN=$FRAME_MEAN
write_config "$FX_CONFIG"$'\n'"$SDR10_CONFIG"
expect_rendered sdr10
expect_rgb_near "sdr10 frame mean against sdr8" "$FRAME_MEAN" "$SDR8_MEAN" "$CHANNEL_TOLERANCE"
write_config "$FX_CONFIG"
expect_rendered sdr8-return
expect_rgb_near "sdr8-return frame mean against sdr8" "$FRAME_MEAN" "$SDR8_MEAN" "$CHANNEL_TOLERANCE"

# -- Phase 2: SDR8 -> SDR10 ---------------------------------------------------
# Headless accepts XR30 or XB30 via wlr_output_test_state (XR30 is tried first),
# so the probe succeeds and the output commits to 10-bit without a fallback reason.
write_config "$SDR10_CONFIG"
expect_color sdr8-to-sdr10 "$SDR10_ACTIVE"
expect_human_sdr10_active sdr8-to-sdr10
echo "sdr8-to-sdr10: probe succeeded, output committed to 10-bit SDR"

# -- Phase 3: HDR (unavailable) -> SDR10 ---------------------------------------
# Configure HDR first (fails on headless). Then switch to bit_depth=10 without
# HDR. The HDR reason must clear and the output must select XR30 or XB30.
write_config $'\n[output.HEADLESS-1]\nhdr = "on"'
expect_color "hdr-to-sdr10 setup" '
  .outputs[0].hdr_requested == true
  and .outputs[0].hdr_active == false
  and (.outputs[0].fallback_reason | length) > 0
  and .outputs[0].render_format == "XR24"'

write_config "$SDR10_CONFIG"
expect_color hdr-to-sdr10 "$SDR10_ACTIVE"'
  and .outputs[0].hdr_requested == false
  and .outputs[0].hdr_active == false
  and .outputs[0].fallback_reason == ""
  and .outputs[0].transfer_function == "none"
  and .outputs[0].primaries == "none"'
echo "hdr-to-sdr10: HDR reason cleared, SDR10 probe succeeded after transition"

# -- Phase 4: HDR unavailable + SDR10 configured -------------------------------
# When HDR and bit_depth=10 are both configured, the HDR probe fails first
# (headless does not advertise PQ or BT.2020), then the SDR10 probe runs
# independently and succeeds. The HDR fallback reason is set, the SDR10 reason is not.
write_config "$SDR10_CONFIG"$'\nhdr = "on"'
expect_color hdr-unavailable-with-sdr10 "$SDR10_ACTIVE"'
  and .outputs[0].hdr_requested == true
  and .outputs[0].hdr_active == false
  and (.outputs[0].fallback_reason | length) > 0'
expect_human_sdr10_active hdr-unavailable-with-sdr10
echo "hdr-unavailable-with-sdr10: HDR reason set, SDR10 probe succeeded independently"

# -- Phase 5: SDR10 -> SDR8 ----------------------------------------------------
# Reverting to the default config (no bit_depth override) must return the
# output to XR24 with no bit_depth_fallback_reason.
write_config
expect_color sdr10-to-sdr8 '
  .outputs[0].configured_bit_depth == 8
  and .outputs[0].bit_depth_fallback_reason == ""
  and .outputs[0].sdr10_active == false
  and .outputs[0].render_format == "XR24"'
echo "sdr10-to-sdr8: output returned to XR24, no bit_depth_fallback_reason"
