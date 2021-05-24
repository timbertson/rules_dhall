#!/usr/bin/env bash
set -eu -o pipefail
DHALL_INJECT='%{DHALL_INJECT}%'
if [ "$#" -lt 1 ]; then
	echo >&2 "Not enough arguments"
	exit 1
fi
action="$1"
shift 1

case "$action" in
	symlink)
		# Note: copied from ./wrapper.sh
		cd "$BUILD_WORKSPACE_DIRECTORY"
		echo "$DHALL_INJECT" | tr ':' '\n' | while true; do
			# place each deps file in the workspace where the dhall file expects it
			read dest || break
			read impl
			mkdir -p "$(dirname "$dest")"
			echo >&2 ln -sfn "$(pwd)/$impl" "$dest"
			ln -sfn "$(pwd)/$impl" "$dest"
		done
		;;

	symlink_cleanup)
		cd "$BUILD_WORKSPACE_DIRECTORY"
		echo "$DHALL_INJECT" | tr ':' '\n' | while true; do
			read dest || break
			read impl
			if [ -L "$dest" ]; then
				echo >&2 rm "$dest"
				rm "$dest"
			else
				echo >&2 "Skipping non-symlink: $dest"
			fi
		done
		;;

	*)
		echo >&2 "Unknown action: $action"
		exit 1
		;;
esac
