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

  [ "${EPOCHSECONDS:-0}" -ge 1 ] || return 4$(
    echo E: "Upgrade your bash shell to version 5 or later." >&2)
  local WEEKDAY_SHORTNAMES=( $( TZ=UTC printf -- '%(%a)T\n' 7{0..6}01337 ) )

  local ORIG_STDOUT_FD= ORIG_STDERR_FD=
  exec {ORIG_STDOUT_FD}>&1
  exec {ORIG_STDERR_FD}>&2

  local -A CFG=(
    [task]=record
    )
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
      --metadata )
        CFG[task]="${VAL#--}"; continue;;
    esac
    echo E: "unsupported argumnts: $OPT" >&2
    return 4
  done

  local PROXY_PROG=
  local SL_PROG_NAME='streamlink'
  local LURK_INTERVAL=15m
  local METADATA_INTERVAL=
  local FAIL_STREAM_DURA_SEC=180
  # ^-- Very short stream = probably just a glitch = retry sooner than usual
  local FAIL_STREAM_RETRY_DELAY=30s
  local FAIL_STREAM_MAX_RETRYS=10
  local BUFSZ=4K
  local QUALI='360p,worst'
  local REC_VIDEO_SUFFIX='.ts'
  local SKIP_ADS= # use the rc to set this to '+' to enable
  local RC=
  for RC in '' "$CHAN"/; do
    for RC in "$RC"{.,}; do
      for RC in "$RC"twitch-lurk.rc; do
        [ ! -f "$RC" ] || source -- "$RC" || return $?
      done
    done
  done

  lurkrec_"${CFG[task]}" "$@" || return $?
}


function lurkrec_record () {
  lurkrec_validate_weekdays_option || return $?
  VAL="${CFG[earliest]}"
  [ -z "$VAL" ] || gxctd "$VAL" "twitch lurk chan=$CHAN $1" || return $?

  mkdir --parents -- "$CHAN"
  [ -d "$CHAN" ] || return 4$(echo E: "Not a directory: $1" >&2)

  local REC_CMD=(
    $PROXY_PROG
    $SL_PROG_NAME
    --ringbuffer-size "$BUFSZ"
    --twitch-disable-hosting
    --twitch-disable-reruns
    ${SKIP_ADS/#'+'/--twitch-disable-ads}
    --stdout
    twitch.tv/"${CHAN,,}"
    "$QUALI"
    )

  local CHECK_UTS= REC_VIDEO_DEST= RV= DURA=
  local FAIL_STREAM_RMN_RETRYS=0
  local DATE_NOW= LOGF_DATE= LOGF_CUR=

  while true; do
    CHECK_UTS="$EPOCHSECONDS"
    printf -v DATE_NOW -- '%(%y%m%d)T' "$CHECK_UTS"

    [ -n "$LOGF_CUR" -a -f "$LOGF_CUR" ] || LOGF_CUR=
    [ "$DATE_NOW" == "$LOGF_DATE" ] || LOGF_CUR=
    if [ -z "$LOGF_CUR" ]; then
      LOGF_DATE="$DATE_NOW"
      LOGF_CUR="$CHAN/log.$LOGF_DATE-$(
        printf -- '%(%H%M%S)T' "$CHECK_UTS")-$$.txt"
      echo D: "Switching to new logfile: $LOGF_CUR"
      exec &> >(LC_TIME=C ts | tee --append -- "$LOGF_CUR" >&$ORIG_STDOUT_FD)
      echo D: "Start new logfile: $LOGF_CUR"
    fi

    lurkrec_try_recording; RV=$?
    DURA="$EPOCHSECONDS"
    (( DURA -= CHECK_UTS ))
    if [ -f "$REC_VIDEO_DEST" -a ! -s "$REC_VIDEO_DEST" ]; then
      echo -n 'Output seems empty? -> '
      ls -l -- "$REC_VIDEO_DEST"
      echo -n 'Delete empty output -> '
      # mv --verbose --no-clobber --no-target-directory \
      #   -- "$REC_VIDEO_DEST"{,.would-have-deleted.debug}
      rm --verbose -- "$REC_VIDEO_DEST"
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

  kill -HUP "$META_DATA_LOG_HELPER_PID" 2>/dev/null || true
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
  local REC_BFN=
  printf -v REC_BFN -- '%s/%(%y%m%d-%H%M%S)T.rec' "$CHAN" "$CHECK_UTS"
  REC_VIDEO_DEST="$REC_BFN$REC_VIDEO_SUFFIX"
  echo D: "${REC_CMD[*]} >'$REC_VIDEO_DEST'"
  >"$REC_VIDEO_DEST" || return $?$(
    echo E: "Failed to record: Cannot create file: $REC_VIDEO_DEST" >&2)
  "${REC_CMD[@]}" >"$REC_VIDEO_DEST" &
  local REC_PID=$!

  META_LOG="$REC_BFN.meta.jsonl" lurkrec_metadata_log_helper &
  local META_DATA_LOG_HELPER_PID=$!
  disown "$META_DATA_LOG_HELPER_PID"

  wait "$REC_PID"; local REC_RV=$?
  kill -HUP -- "$META_DATA_LOG_HELPER_PID" 2>/dev/null || true

  return "$REC_RV"
}


function lurkrec_metadata () {
  local URL="twitch.tv/${CHAN,,}"
  local SL_CMD=(
    $PROXY_PROG
    $SL_PROG_NAME
    --json
    "$URL"
    )
  local SED='s~\n~~g;s~\}$~\t&\n~'
  local JSON="$( "${SL_CMD[@]}" | jq --tab .metadata | sed -zre "$SED" )"
  [[ "$JSON" == '{'*'}' ]] || return 4$(
    echo E: "Failed to detect stream metadata for: $URL" >&2)
  echo "$JSON"
}


function lurkrec_metadata_log_helper () {
  # First. wait until we actually have video data: We wouldn't want to
  # create a meta data log file for a failed recording.
  [ -f "$REC_VIDEO_DEST" ] || return 4$(echo E: $FUNCNAME: >&2 \
    "REC_VIDEO_DEST='$REC_VIDEO_DEST' is not a regular file!")
  while kill -0 -- "$REC_PID" 2>/dev/null && [ ! -s "$REC_VIDEO_DEST" ]; do
    sleep 1s
  done

  local NOW= META= INTV="$METADATA_INTERVAL"
  [ -n "$INTV" ] || INTV="$LURK_INTERVAL"

  local ERROR_PLACEHOLDER='null'
  local PREV="$ERROR_PLACEHOLDER"

  while kill -0 -- "$REC_PID" 2>/dev/null ; do
    META="$(lurkrec_metadata)"
    NOW="$EPOCHSECONDS"
    if [ -z "$META" ]; then
      echo "[metadata] error! previous: $PREV"
      META='{ "!":'" $NOW }"
    elif [ "$META" == "$PREV" ]; then
      echo "[metadata] same: $META"
      META='{ "=":'" $NOW }"
    else
      echo "[metadata] updated: $META previous: $PREV"
      PREV="$META"
    fi
    [ -z "$META_LOG" ] || (
      printf '{\t"lurkrec_date": "%(%F %T)T",' "$NOW"
      printf '\t"lurkrec_uts": %s,' "$NOW"
      echo "${META#'{'}"
      ) >>"$META_LOG" || true
    sleep "$INTV" || return 4$(
      echo E: $FUNCNAME: "Failed to sleep for '$INTV'" >&2)
  done
}










lurkrec_cli_main "$@"; exit $?
