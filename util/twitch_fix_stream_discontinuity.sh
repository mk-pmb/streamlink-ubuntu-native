#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function video_codec_fix_twitch () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  exec </dev/null

  [ "$1" == --netfs ] && shift || df --local . >/dev/null || return 4$(
    echo E: 'flinching from operating on a remote filesystem.' \
      'Use --netfs as first argument to override.' >&2)

  [ "$1" != -- ] || shift
  local SUF_BROKEN='.b0rken-orig'
  local SUF_FIXED='.fixed'
  local ITEM= VAL=
  local INPUT_SUF= # original input filename extension
  local BROKEN_BFN=
  local OUT_DEST=
  local MV='mv --verbose --no-clobber --'
  for ITEM in "$@"; do
    INPUT_SUF="${ITEM##*.}"
    [ "$INPUT_SUF" == "$ITEM" ] && INPUT_SUF=
    case "${#INPUT_SUF}:$INPUT_SUF" in
      2:ts ) ;; # MPEG TS
      [0-9]:*[^a-z0-9]* ) INPUT_SUF='!character(s)';;
      [3-6]:* ) ;;
      * ) INPUT_SUF='!length';;
    esac
    [ "${INPUT_SUF:0:1}" != '!' ] || return 3$(
      echo E: "Unsupported suffix: Unexpected ${INPUT_SUF:1}: $ITEM" >&2)
    local BROKEN_BFN="${ITEM%.$INPUT_SUF}"
    case "$BROKEN_BFN" in
      *"$SUF_FIXED" ) echo D: skip "'*$SUF_FIXED' file: $ITEM"; continue;;
      *"$SUF_BROKEN".* ) echo D: skip "'*$SUF_BROKEN.*' file: $ITEM"; continue;;
    esac
    BROKEN_BFN+="$SUF_BROKEN"

    VAL="$(head --bytes=64 -- "$ITEM" | tr '\0' .)"
    case "$VAL" in
      G@.?..* ) ;; # Twitch stream header 2024-12-27

      ?PNG$'\r\n'* | \
      *JFIF* | \
      $'\n'* | \
      $'\r\n'* | \
      $'\xEF\xBB\xBF'* | \
      __probably_not_a_video__ )
        echo D: skip "file that seems to not be a video: $ITEM"
        continue;;

      '... ftypisom...'* | \
      *'isomiso2avc1mp41'* | \
      *'isomiso2mp41'* | \
      __looks_like_ffmpeg_reencoded__ )
        # NB: The "avc1" does not mean the video codec.
        echo D: skip "file that looks like it was encoded using ffmpeg: $ITEM"
        continue;;

      ...?ftypmp42....isommp42* | \
      __looks_like_youtube_encoded__ )
        echo D: skip "file that looks like it was encoded by YouTube: $ITEM"
        continue;;

      ...?ftyp* ) ;;
      * )
        echo D: skip "file with no ftyp header: $ITEM"
        continue;;
    esac

    VAL="$(quick_cheap_fuser "$ITEM")" || return $?
    [ -z "$VAL" ] || continue$(echo W: >&2 \
      "skip: probably in use by PID ${VAL//$'\n'/, }: $ITEM")

    check_avail_disk_space "$ITEM" || return $?

    for VAL in "$BROKEN_BFN".{done,wip}."$INPUT_SUF" ; do
      # ^- Check 'wip' last so we can use VAL after loop.
      [ -e "$VAL" ] || continue
      echo E: "File already exists: $VAL" >&2
      return 4
    done
    # VAL is now the WIP file name.
    $MV "$ITEM" "$VAL" || return $?
    OUT_DEST="$ITEM"
    OUT_DEST="${OUT_DEST/%.ts/.mp4}"
    ffmpeg -hide_banner -i "$VAL" -c copy "$OUT_DEST" || return $?$(
      echo E: "Failed to convert (rv=$?) $VAL" >&2)
    $MV "$VAL" "$BROKEN_BFN.done.$INPUT_SUF" || return $?
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


function check_avail_disk_space () {
  local SRC="$1"; shift
  local DEST="${1:-$SRC}"; shift
  local UNIT='--block-size=M'
  local NEED="$(du $UNIT -- "$SRC" | grep -oPe '^\s*\d+')"
  NEED="${NEED//[^0-9]/}"
  local AVAIL="$(df $UNIT --output=avail -- "$DEST" | grep -oPe '^\s*\d+')"
  AVAIL="${AVAIL//[^0-9]/}"
  [ "$AVAIL" -ge "$NEED" ] || return 2$(echo E: >&2 \
    "Not enough space ($AVAIL < $NEED ${UNIT#*=}B) to convert $ITEM")
}


video_codec_fix_twitch "$@"; exit $?
