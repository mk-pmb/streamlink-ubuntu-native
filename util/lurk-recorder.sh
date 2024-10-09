#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function lurk_recorder () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  # local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  # cd -- "$SELFPATH" || return $?

  local CHAN="$1"; shift
  [[ "$CHAN" == [a-z]* ]] || return 4$(
    echo E: "Channel name (arg 1) must start with a letter!" \
      "(Options go behind.)" >&2)
  CHAN="${CHAN%/}"
  mkdir --parents -- "$CHAN"
  [ -d "$CHAN" ] || return 4$(echo E: "Not a directory: $1" >&2)

  case "$1" in
    --earliest=* )
      gxctd "${1#*=}" "twitch lurk chan=$CHAN $1" || return $?
      shift;;
  esac
  [ "$#" == 0 ] || return 4$(echo E: "unsupported argumnts: $*" >&2)

  local LOGF="$CHAN/log.$(date +%y%m%d-%H%M%S)-$$.txt"
  local PROXY_PROG=
  local LURK_INTERVAL=15m
  local FAIL_STREAM_DURA_SEC=180
  # ^-- Very short stream = probably just a glitch = retry sooner than usual
  local FAIL_STREAM_RETRY_DELAY=30s
  local FAIL_STREAM_MAX_RETRYS=10
  local BUFSZ=4K
  local QUALI='360p,worst'
  local SKIP_ADS= # use the rc to set this to '+' to enable
  local RC=
  for RC in '' "$CHAN"/; do
    for RC in "$RC"{.,}; do
      for RC in "$RC"twitch-lurk.rc; do
        [ ! -f "$RC" ] || source -- "$RC" || return $?
      done
    done
  done

  exec &> >(ts | tee -- "$LOGF")

  local REC_CMD=(
    $PROXY_PROG
    streamlink
    --ringbuffer-size "$BUFSZ"
    --twitch-disable-hosting
    --twitch-disable-reruns
    ${SKIP_ADS/#'+'/--twitch-disable-ads}
    --stdout
    twitch.tv/"${CHAN,,}"
    "$QUALI"
    )

  local DEST= RV= DURA=
  local FAIL_STREAM_RMN_RETRYS=0
  while true; do
    SECONDS=0
    printf -v DEST -- '%s/%(%y%m%d-%H%M%S)T.rec.mp4' "$CHAN"
    echo D: "${REC_CMD[*]} >'$DEST'"
    "${REC_CMD[@]}" >"$DEST"
    RV=$?
    DURA="$SECONDS"
    if [ -f "$DEST" -a ! -s "$DEST" ]; then
      echo -n 'Output seems empty? -> '
      ls -l -- "$DEST"
      echo -n 'Delete empty output -> '
      # mv --verbose --no-clobber --no-target-directory \
      #   -- "$DEST"{,.would-have-deleted.debug}
      rm --verbose -- "$DEST"
    fi
    echo -n D: "rv=$RV after $DURA sec => "
    if [ "$SECONDS" -gt "$FAIL_STREAM_DURA_SEC" ]; then
      FAIL_STREAM_RMN_RETRYS="$FAIL_STREAM_MAX_RETRYS"
      echo "long stream. reset fail stream retrys to $FAIL_STREAM_RMN_RETRYS."
    fi
    echo "$FAIL_STREAM_RMN_RETRYS fail stream retry(s) remaining. => "
    if [ "$FAIL_STREAM_RMN_RETRYS" -ge 1 ]; then
      echo "wait $FAIL_STREAM_RETRY_DELAY."
      sleep "$FAIL_STREAM_RETRY_DELAY" || return $?
      (( FAIL_STREAM_RMN_RETRYS -= 1 ))
    else
      echo "off-stream lurk. => wait $LURK_INTERVAL."
      sleep "$LURK_INTERVAL" || return $?
    fi
  done
}










lurk_recorder "$@"; exit $?
