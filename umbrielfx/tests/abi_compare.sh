#!/bin/sh -eu
# Compares the two abi probe builds. Field offsets must match exactly; umbrielfx
# may only be larger, never smaller or differently ordered.
#
# Usage: abi_compare.sh <wlroots-probe> <umbrielfx-probe>

wlroots_probe=$1
umbrielfx_probe=$2

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$wlroots_probe" > "$tmp/wlroots"
"$umbrielfx_probe" > "$tmp/umbrielfx"

status=0

# Every field wlroots declares must sit at the same offset in umbrielfx.
grep '^offsetof' "$tmp/wlroots" > "$tmp/wlroots.off"
grep '^offsetof' "$tmp/umbrielfx" > "$tmp/umbrielfx.off"
if ! diff -u "$tmp/wlroots.off" "$tmp/umbrielfx.off" > "$tmp/off.diff"; then
	echo "error: umbrielfx scene struct field offsets diverge from wlroots"
	echo "       The compositor calls scene helpers umbrielfx does not reimplement"
	echo "       (wlr_scene_xdg_surface_create, wlr_scene_subsurface_tree_create,"
	echo "       wlr_scene_attach_output_layout, ...) which resolve to libwlroots"
	echo "       and read these structs at wlroots offsets. A mismatch corrupts"
	echo "       memory silently."
	echo
	sed 's/^/  /' "$tmp/off.diff"
	echo
	echo "  Fix the field order in umbrielfx/include/umbrielfx/types/wlr_scene.h."
	echo "  Fields Umbriel adds belong after every wlroots field."
	status=1
fi

# umbrielfx extends these structs, so it must never be smaller than wlroots.
grep '^sizeof' "$tmp/wlroots" > "$tmp/wlroots.size"
while read -r line; do
	name=$(printf '%s\n' "$line" | sed 's/^sizeof(struct \([a-z_]*\)).*/\1/')
	want=$(printf '%s\n' "$line" | sed 's/.*>= //')
	got=$(grep "^sizeof(struct $name)" "$tmp/umbrielfx" | sed 's/.*>= //')
	if [ "$got" -lt "$want" ]; then
		echo "error: struct $name is $got bytes in umbrielfx, $want in wlroots"
		echo "       umbrielfx extends this struct and can never be smaller."
		status=1
	fi
done < "$tmp/wlroots.size"

exit $status
