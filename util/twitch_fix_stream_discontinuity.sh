#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function video_codec_fix_twitch () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  exec </dev/null

  [ "$1" == --netfs ] && shift || df --local . >/dev/null || return 4$(
    echo E: 'flinching from operating on a remote filesystem.' \
      'Use --netfs as first argument to override.' >&2)

  [ "$1" != -- ] || shift
  local ORIGSUF='.b0rken-orig'
  local SEMISUF='.fixed'
  local ITEM= SUF= BFN= VAL=
  local MV='mv --verbose --no-clobber --'
  for ITEM in "$@"; do
    SUF="${ITEM##*.}"
    [ "$SUF" == "$ITEM" ] && SUF=
    case "${#SUF}:$SUF" in
      [^3-6]:* ) SUF='!length';;
      [0-9]:*[^a-z0-9]* ) SUF='!character(s)';;
    esac
    [ "${SUF:0:1}" != '!' ] || return 3$(
      echo "E: Unsupported suffix: Unexpected ${SUF:1}: $ITEM" >&2)
    local BFN="${ITEM%.$SUF}"
    case "$BFN" in
      *"$SEMISUF" ) echo "D: skip '*$SEMISUF' file: $ITEM"; continue;;
      *"$ORIGSUF".* ) echo "D: skip '*$ORIGSUF.*' file: $ITEM"; continue;;
    esac

    VAL="$(head --bytes=64 -- "$ITEM" | tr '\0' .)"
    case "$VAL" in
      '... ftypisom...'* | \
      *'isomiso2avc1mp41'* | \
      __looks_like_ffmpeg_reencoded__ )
        # NB: The "avc1" does not mean the video codec.
        echo "D: skip file that looks like it was encoded using ffmpeg: $ITEM"
        continue;;
    esac

    BFN+="$ORIGSUF"

    VAL="$(quick_cheap_fuser "$ITEM")" || return $?
    [ -z "$VAL" ] || continue$(echo W: >&2 \
      "skip: probably in use by PID ${VAL//$'\n'/, }: $ITEM")

    for VAL in wip done; do
      VAL="$BFN.$VAL.$SUF"
      [ -e "$VAL" ] || continue
      echo E: "File already exists: $VAL" >&2
      return 4
    done
    VAL="$BFN.wip.$SUF"
    $MV "$ITEM" "$VAL" || return $?
    ffmpeg -i "$VAL" -c copy "$ITEM" || return $?
    $MV "$VAL" "$BFN.done.$SUF" || return $?
  done
}


function quick_cheap_fuser () {
  # I'd use the real `fuser` command but unfortunately it often gets stuck
  # for minutes when I have totally unrelated sshfs mounts.
  # Stuck so hard not even `kill -SIGKILL` can help.
  # So in comparison, overall, this hack here is more reliable in my case.
  local REL= ABS=
  local FIND=(
    find /proc
    -mindepth 3 -maxdepth 3 -path "/proc/[0-9]*/fd/[0-9]*" -type l
    '(' -false
    )
  for REL in "$@"; do
    ABS="$(readlink -f -- "$REL")"
    [ -f "$ABS" ] || return 4$(echo E: $FUNCNAME: >&2 \
      "Cannot determine absolute path of: $REL")
    FIND+=( -o -lname "$ABS" )
  done
  FIND+=( ')' )
  "${FIND[@]}" 2>/dev/null | cut -d / -sf 3 | sort -gu || true
}


video_codec_fix_twitch "$@"; exit $?
