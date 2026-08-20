#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
#
# Early versions of `lurk-recorder.sh` used `>(LANG=C ts | tee --append …)`
# for logging, but those subprocesses had a tendency to stay around because
# they didn't detect end of data on their input channel.
# Trying to kill the old pipe turned out more complicated than expected.
#
# By implementing our own logtee, we can simply set a read timeout that
# allows us to check whether this logger subprocess is still required.
# The parent process could keep track of the logger child and notify it
# via SIGHUP when no longer needed, but having that responsibility on the
# parent could become a problem if the parent is too busy doing other stuff.
# Instead, we let the parent use a symlink, or one of its `/proc/$$/fd/*`,
# to indicate which logfile is the current one. That way, we can trivially
# compare whether the indicator still points to the same file as our stdout.


function logtee () {
  local STDOUT_SAME_AS="$1"
  [ "$STDOUT_SAME_AS" -ef /proc/self/fd/1 ] || return 4$(
    echo E: "Destination indicator (CLI arg 1 = $(
      stat -c '%F %N' -- "$STDOUT_SAME_AS" 2>&1
      )) must initially point to the same thing as stdout ($(
      stat -c '%F %N' -- /proc/self/fd/1 2>&1))." >&2)
  local LN= RV=
  while true; do
    LN=
    IFS= read -r -t 10 LN
    RV=$?
    if [ "$RV" -gt 128 ]; then # read timeout
      [ "$STDOUT_SAME_AS" -ef /proc/self/fd/1 ] || break
      continue
    fi
    [ "$RV" == 0 ] || break
    [ -n "$LN" ] || continue
    LN="$(printf -- '%(%F %T)T' -1) $LN"
    echo "$LN"
    echo "$LN" >&2
  done
}






logtee "$@"; exit $?
