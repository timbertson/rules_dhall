#!/usr/bin/env bash
set -eu -o pipefail
if [ "${DEBUG:-}" = 1 ]; then
	echo "+ DEPS=$DEPS" >&2
	echo "+ DHALL_CACHE_ARCHIVES=$DHALL_CACHE_ARCHIVES" >&2
	set -x
else
	DEBUG=0
fi
mkdir -p .cache/dhall

echo "$DHALL_CACHE_ARCHIVES" | tr ':' '\n' | while read f; do
	if [ -n "$f" -a -f "$f" ]; then
		tar xf "$f" -C .cache/dhall
	fi
done

# Debug
if [ "$DEBUG" = 1 ]; then
	find .cache >&2
fi

# TODO can we use the user's home dir (impurely) for this?
export XDG_CACHE_HOME="$(pwd)/.cache"
export XDG_CACHE_PATH="${XDG_CACHE_PATH:-}:$(pwd)/.cache"

if [ -n "${CAPTURE_HASH:-}" ]; then
	# CAPTURE_HASH tells us what filename to use
	hash_expr="$(cat "$CAPTURE_HASH")"
	hash_filename="${hash_expr/sha256:/1220}"
	if [ -z "$hash_filename" ]; then
		echo >&2 "Error: $CAPTURE_HASH file does not contain a hash"
		exit 1
	fi
	"$@" > "$hash_filename"

	# write a binary file for efficient importing
	echo "missing $hash_expr" > "$BINARY_FILE"

	# we wrap the cache in a tarfile because the exact name matters
	tar cf "$OUTPUT_TO" "$hash_filename"
else
	if [ -n "$OUTPUT_TO" ]; then
		exec > "$OUTPUT_TO"
	fi
	exec "$@"
fi

