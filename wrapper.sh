#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function sl_wrap () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  # cd -- "$SELFPATH" || return $?

  local VSL="$SELFPATH/venv/bin/streamlink"
  [ ! -x "$VSL" ] || exec "$VSL" "$@" ||
    echo W: "streamlink wrapper: Failed to exec '$VSL' (rv=$?)," \
      "will try the regular invocation as fallback." >&2

  local SL_REPO="$STREAMLINK_REPO_PATH"
  [ -n "$SL_REPO" ] || SL_REPO="$SELFPATH/sl-repo"
  local SL_MAIN="$SL_REPO/src/streamlink_cli/main.py"
  [ -d "$SL_REPO" ] || return 4$(
    echo "H: Did you clone and symlink the streamlink repo?" >&2
    echo "E: Not a directory: $SL_REPO" >&2)
  [ -f "$SL_MAIN" ] || return 4$(echo "E: Not a file: $SL_MAIN" >&2)

  sl_core "$@" || return $?
}



function sl_core () {
  local PYPA="$SL_REPO/src"
  PYPA+=":$SELFPATH/shims"
  PYPA+=":$SELFPATH/upgrades/lib"
  export PYTHONPATH="$PYPA"
  python3 -m streamlink_cli "$@" || return $?
}










sl_wrap "$@"; exit $?
