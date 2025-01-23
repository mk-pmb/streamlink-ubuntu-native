#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function lurkrec_cli_main () {
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

  [ "${EPOCHSECONDS:-0}" -ge 1 ] || return 4$(
    echo E: "Upgrade your bash shell to version 5 or later." >&2)
  local WEEKDAY_SHORTNAMES=( $( TZ=UTC printf -- '%(%a)T\n' 7{0..6}01337 ) )

  local -A CFG=()
  local KEY= VAL=
  while [ "$#" -ge 1 ]; do
    VAL="$1"; shift
    case "$VAL" in
      --weekdays=* | \
      --earliest=* | \
      --= )
        VAL="${VAL#--}"
        CFG["${VAL%%=*}"]="${VAL#*=}"
        continue;;
    esac
    echo E: "unsupported argumnts: $OPT" >&2
    return 4
  done

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

  lurkrec_validate_weekdays_option || return $?
  VAL="${CFG[earliest]}"
  [ -z "$VAL" ] || gxctd "$VAL" "twitch lurk chan=$CHAN $1" || return $?

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

  local CHECK_UTS= DEST= RV= DURA=
  local FAIL_STREAM_RMN_RETRYS=0
  while true; do
    CHECK_UTS="$EPOCHSECONDS"
    lurkrec_try_recording; RV=$?
    DURA="$EPOCHSECONDS"
    (( DURA -= CHECK_UTS ))
    if [ -f "$DEST" -a ! -s "$DEST" ]; then
      echo -n 'Output seems empty? -> '
      ls -l -- "$DEST"
      echo -n 'Delete empty output -> '
      # mv --verbose --no-clobber --no-target-directory \
      #   -- "$DEST"{,.would-have-deleted.debug}
      rm --verbose -- "$DEST"
    fi
    echo -n D: "rv=$RV after $DURA sec => "
    if [ "$DURA" -gt "$FAIL_STREAM_DURA_SEC" ]; then
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


function lurkrec_validate_weekdays_option () {
  local VAL="${CFG[weekdays]}"
  [ -n "$VAL" ] || return 0

  # Starting the weekdays list with /^[+-][12]?[0-9]h,/ lets you declare
  # that this streamer's schedule uses another timezone for the purpose of
  # assigning weekday names to their streams.
  #
  # Example: Streamer "Gronkh" uses timezone Europe/Berlin for all regular
  # time-related stuff, but his Friday streams may easily continue until
  # noon of the next day. So if you're using Berlin time, too, it means
  # you want a weekday check performed at 11:59 am on Saturday to still
  # give "Fri" as the result. To achieve that, you'd use "-12h,Fri".
  # That way, 11:59 am becomes negative(!) 00:01 am, i.e. 11:59 pm of
  # the previous day, making it Friday.
  #
  CFG[weekdays_offset_hours]=0
  case "$VAL" in
    [+-][12][0-9]h,* | [+-][0-9]h,* )
      CFG[weekdays_offset_hours]="${VAL%%h,*}"
      VAL="${VAL#*,}";;
  esac

  local ERR="Option --weekdays=: !"
  ERR+=" Expected a list (separated by space or comma) of any of:"
  ERR+=" ${WEEKDAY_SHORTNAMES[*]}"

  VAL="${VAL//,/ }"
  local ACCEPT=" ${WEEKDAY_SHORTNAMES[*]} " # We'll use both spaces later.
  local BAD="${VAL//[$ACCEPT]/}"
  [ -z "$BAD" ] || return 4$(echo E: "${ERR/!/Unsupported characters.}" >&2)
  local VALID=
  for VAL in $VAL; do
    [[ "$ACCEPT" == *" $VAL"* ]] || return 4$(
      echo E: "${ERR/!/"Unsupported weekday short name '$VAL'."}" >&2)
    VALID+="$VAL,"
  done
  [ -n "$VALID" ] || return 4$(
      echo E: "${ERR/!/Found no weekday short names in that list.}" >&2)
  CFG[weekdays]="${VALID%,}"
}


function lurkrec_check_weekdays_option () {
  local ACCEPT="${CFG[weekdays]}"
  [ -n "$ACCEPT" ] || return 0
  local VAL="${CFG[weekdays_offset_hours]:-0}"
  (( VAL *= 3600 )) # hours -> seconds
  (( VAL += CHECK_UTS ))
  printf -v VAL -- '%(%a)T' "$VAL"
  [[ ",$ACCEPT," == *",$VAL,"* ]] || return $?$(
    echo W: "Flinching: Weekday in stream schedule timezone is '$VAL'," \
      "which is not in the list '$ACCEPT'." >&2)
}


function lurkrec_try_recording () {
  lurkrec_check_weekdays_option || return $?
  printf -v DEST -- '%s/%(%y%m%d-%H%M%S)T.rec.mp4' "$CHAN" "$CHECK_UTS"
  echo D: "${REC_CMD[*]} >'$DEST'"
  "${REC_CMD[@]}" >"$DEST" || return $?
}










lurkrec_cli_main "$@"; exit $?
