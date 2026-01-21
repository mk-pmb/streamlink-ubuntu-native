#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function vcfr_cli_main () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local TASK='autofix'
  case "$1" in
    --identify | \
    --task=* ) TASK="${1#--}"; TASK="${TASK#*=}"; shift;;
  esac
  vcft_"$TASK" "$@"; return $?
}


function vcft_autofix () {
  exec </dev/null
  [ "$1" == --netfs ] && shift || df --local . >/dev/null || return 4$(
    echo E: 'flinching from operating on a remote filesystem.' \
      'Use --netfs as first argument to override.' >&2)

  local FLAGS=,
  if [ "$1" == --same-time ]; then FLAGS+="${1#--},"; shift; fi

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

    VAL="$(vcft_identify "$ITEM")"
    VAL="${VAL#"$ITEM"$'\t'}"
    case "$VAL" in
      '' ) continue;;
      'twitch_stream, as_seen_on='* ) ;;
      'isom, lamestart' ) ;;
      'isom, faststart' )
        echo D: skip "already faststart, file: $ITEM"
        continue;;
      * )
        echo D: skip "strange type: $VAL, file: $ITEM"
        continue;;
    esac

    VAL="${CHEAP_FUSER_CMD:-fuser-file-cheap-quick}"
    VAL="$("$VAL" "$ITEM")" || return $?
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
    ITEM=
    case "$OUT_DEST" in
      *.mp4 ) ITEM='-movflags faststart';;
    esac
    ffmpeg -hide_banner -i "$VAL" -c copy $ITEM "$OUT_DEST" || return $?$(
      echo E: "Failed to convert (rv=$?) $VAL" >&2)
    case "$FLAGS" in
      *,same-time,* ) touch --reference="$VAL" -- "$OUT_DEST" || true;;
    esac
    $MV "$VAL" "$BROKEN_BFN.done.$INPUT_SUF" || return $?
  done
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


function vcft_decode_big_endian () {
  # expected arguments: offset (bytes), length (bytes)
  od -t d4 -An --endian=big -j "$1" -N "$2" -- "$3" | tr -cd 0-9
}


function vcft_identify () {
  while [ "$#" -ge 2 ]; do "$FUNCNAME" "$1" || return $?; shift; done
  local SRC="$1"
  echo -n "$SRC"$'\t'
  local REREAD="echo $(head --bytes=48 -- "$SRC" | base64) | base64 -d"
  # ^-- Stash away so we can cope with a pipe as input.
  #     We don't need quotes around $() because because base64 only uses
  #     /+= as special characters and they are safe for echo arguments.

  local BUF="$(eval "$REREAD" | tr '\0\177-\377' .)"
  # Conflating the null byte with a dot can cause false positives but seems
  # good enough for realistic usecases.
  case "$BUF" in
    G@.?..* | \
    . ) echo 'twitch_stream, as_seen_on=2024-12-27'; return 0;;

    ...?ftypmp42....isommp42* | \
    . ) echo 'youtube, as_seen_on=2024-12-27'; return 0;;

    ?PNG$'\r\n'* | \
    *JFIF* | \
    . ) echo 'probably_image_file'; return 0;;

    $'\n'* | \
    $'\r\n'* | \
    $'\xEF\xBB\xBF'* | \
    . ) echo 'probably_text_file'; return 0;;

    ..??ftypisom..* ) ;;
    * ) echo 'probably_not_mp4_video, no_ftyp_box'; return 0;;
  esac

  # Previous case fell through, so it's an isom file.
  local OFFSET=0 BOX_LEN=0
  local BOX_TYPE= HAD_BOX_TYPES=
  while [ "$OFFSET" -lt "${#BUF}" ]; do
    BOX_LEN="$(eval "$REREAD" | vcft_decode_big_endian $OFFSET 4 -)"
    BOX_TYPE="${BUF:$OFFSET+4:4}"
    HAD_BOX_TYPES+=",$BOX_TYPE,"
    # printf -- 'D: %q\t%s\t%q\n' "$BOX_TYPE" "$BOX_LEN" "$HAD_BOX_TYPES"
    (( OFFSET += BOX_LEN ))
  done
  HAD_BOX_TYPES="${HAD_BOX_TYPES//,free,/}"
  case "$HAD_BOX_TYPES" in
    ,ftyp,,moov,* ) echo 'isom, faststart';;
    ,ftyp,,dat* ) echo 'isom, lamestart';;
    * ) echo "isom, unknown=$HAD_BOX_TYPES";;
  esac
}








vcfr_cli_main "$@"; exit $?
