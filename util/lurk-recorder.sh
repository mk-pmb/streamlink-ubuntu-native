#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function lurkrec_cli_main () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  # cd -- "$SELFPATH" || return $?

  local CHAN="$1"; shift
  [[ "$CHAN" == [a-z]* ]] || return 4$(
    echo E: "Channel name (arg 1) must start with a letter!" \
      "(Options go behind.)" >&2)
  CHAN="${CHAN%/}"
  local SUBDIR="$CHAN"
  [ "${CHAN/,/}" == "$CHAN" ] || CHAN="${CHAN#*,}${CHAN%%,*}"
  CHAN="${CHAN,,}"

  [ "${EPOCHSECONDS:-0}" -ge 1 ] || return 4$(
    echo E: "Upgrade your bash shell to version 5 or later." >&2)
  local WEEKDAY_SHORTNAMES=( $( TZ=UTC printf -- '%(%a)T\n' 7{0..6}01337 ) )

  local ORIG_STDOUT_FD= ORIG_STDERR_FD=
  exec {ORIG_STDOUT_FD}>&1
  exec {ORIG_STDERR_FD}>&2
  exec {LOGF_FD}</dev/null # just find the next unused FD.

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
  local QUALI="${LURKREC_QUALI:-360p30,360p,worst}"
  local REC_VIDEO_SUFFIX='.ts'
  local SKIP_ADS= # Option --twitch-disable-ads has been disabled anyway.
  local WATCHDOG_WITH_ADS_TOL_SEC=30
  local WATCHDOG_SKIP_ADS_TOL_SEC=$(( 8 * 60 ))
  local RC=
  for RC in '' "$SUBDIR"/; do
    for RC in "$RC"{.,}; do
      for RC in "$RC"twitch-lurk.rc; do
        [ ! -f "$RC" ] || source -- "$RC" || return $?
      done
    done
  done

  lurkrec_"${CFG[task]}" "$@" || return $?
}


function lurkrec_named_sleep () {
  local SLEEP_NAME="$1"; shift
  : <(exec -a {twrec-lurk-"$SLEEP_NAME"-,}sleep "$@"); wait $!; return $?
  # Forking as I/O redirect makes the shell ignore the exit status of the
  # child process, i.e. not print the signal name. We could also achive
  # that with `disown`, but then we couldn't `wait`. Or we could force a
  # double subshell, but that would create two heavy forks of our process.
}


function lurkrec_record () {
  lurkrec_validate_weekdays_option || return $?
  VAL="${CFG[earliest]}"
  [ -z "$VAL" ] || gxctd "$VAL" "twitch lurk chan=$SUBDIR $1" || return $?

  mkdir --parents -- "$SUBDIR"
  [ -d "$SUBDIR" ] || return 4$(echo E: "Not a directory: $1" >&2)

  local REC_CMD=(
    $PROXY_PROG
    $SL_PROG_NAME
    --ringbuffer-size "$BUFSZ"
    ${SKIP_ADS/#'+'/--twitch-disable-ads}
    --stdout
    twitch.tv/"$CHAN"
    "$QUALI"
    )

  local CHECK_UTS= REC_VIDEO_DEST= RV= DURA=
  local FAIL_STREAM_RMN_RETRYS=0
  local DATE_NOW= LOGF_DATE= LOGF_CUR=

  while true; do
    CHECK_UTS="$EPOCHSECONDS"
    printf -v DATE_NOW -- '%(%y%m%d)T' "$CHECK_UTS"

    [ -f "$LOGF_CUR" ] || LOGF_CUR=
    [ "$DATE_NOW" == "$LOGF_DATE" ] || LOGF_CUR=
    if [ -z "$LOGF_CUR" ]; then # rotate the log
      LOGF_DATE="$DATE_NOW"
      LOGF_CUR="$SUBDIR/log.$LOGF_DATE-$(
        printf -- '%(%H%M%S)T' "$CHECK_UTS")-$$.txt"
      echo D: "Switching to new logfile: $LOGF_CUR"
      exec >>"$LOGF_CUR"
      eval "exec $LOGF_FD>&1"
      exec &> >(exec "$SELFPATH"/logtee.sh "/proc/$$/fd/$LOGF_FD" \
        >&"$LOGF_FD" 2>&"$ORIG_STDOUT_FD")
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
      echo -n 'long stream.' \
        "Reset fail stream retrys to $FAIL_STREAM_MAX_RETRYS. => "
      FAIL_STREAM_RMN_RETRYS="$FAIL_STREAM_MAX_RETRYS"
    fi
    echo -n "$FAIL_STREAM_RMN_RETRYS fail stream retry(s) remaining. "
    if [ "$RV" -ge 128 ]; then
      echo 'Recorder was killed by a signal, probably from watchdog.' \
        '=> Retry instantly.'
    elif [ "$FAIL_STREAM_RMN_RETRYS" -ge 1 ]; then
      echo "=> Wait $FAIL_STREAM_RETRY_DELAY."
      lurkrec_named_sleep fail-retry "$FAIL_STREAM_RETRY_DELAY" || return $?
      (( FAIL_STREAM_RMN_RETRYS -= 1 ))
    else
      echo "=> Off-stream lurk. => wait $LURK_INTERVAL."
      lurkrec_named_sleep off-stream "$LURK_INTERVAL" || return $?
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
  printf -v REC_BFN -- '%s/%(%y%m%d-%H%M%S)T.rec' "$SUBDIR" "$CHECK_UTS"
  REC_VIDEO_DEST="$REC_BFN$REC_VIDEO_SUFFIX"
  echo D: "${REC_CMD[*]} >'$REC_VIDEO_DEST'"
  >"$REC_VIDEO_DEST" || return $?$(
    echo E: "Failed to record: Cannot create file: $REC_VIDEO_DEST" >&2)
  exec "${REC_CMD[@]}" >"$REC_VIDEO_DEST" &
  local REC_PID=$!
  local BG_HELPER_PIDS=

  META_LOG="$REC_BFN.meta.jsonl" lurkrec_metadata_log_helper & disown $!
  BG_HELPER_PIDS+=" $!"

  lurkrec_file_growth_watchdog & disown $!
  BG_HELPER_PIDS+=" $!"

  wait "$REC_PID"; local REC_RV=$?
  kill -HUP -- $BG_HELPER_PIDS 2>/dev/null || true

  return "$REC_RV"
}


function lurkrec_metadata () {
  local URL="twitch.tv/$CHAN"
  local SL_CMD=(
    $PROXY_PROG
    $SL_PROG_NAME
    --json
    "$URL"
    )
  local JSON="$( "${SL_CMD[@]}" |
    python3 "$SELFPATH"/stream_metadata_sort.py )"
  [[ "$JSON" == '{'*'}' ]] || return 4$(
    echo E: "Failed to detect stream metadata for: $URL" >&2)
  JSON="${JSON//$'\n'/$'\t'}"
  echo "$JSON"
}


function lurkrec_metadata_log_helper () {
  # First. wait until we actually have video data: We wouldn't want to
  # create a meta data log file for a failed recording.
  [ -f "$REC_VIDEO_DEST" ] || return 4$(echo E: $FUNCNAME: >&2 \
    "REC_VIDEO_DEST='$REC_VIDEO_DEST' is not a regular file!")
  while kill -0 -- "$REC_PID" 2>/dev/null && [ ! -s "$REC_VIDEO_DEST" ]; do
    lurkrec_named_sleep loghelper-init 1s
  done

  local NOW= META= INTV="$METADATA_INTERVAL"
  [ -n "$INTV" ] || INTV="$LURK_INTERVAL"

  local ERROR_PLACEHOLDER='null'
  local PREV="$ERROR_PLACEHOLDER"
  local SHORT_PREV="$PREV"

  while kill -0 -- "$REC_PID" 2>/dev/null ; do
    META="$(lurkrec_metadata)"
    NOW="$EPOCHSECONDS"
    if [ -z "$META" ]; then
      echo "[metadata] error! previous: $SHORT_PREV"
      META='"!"'
    elif [ "$META" == "$PREV" ]; then
      echo "[metadata] same: $SHORT_PREV"
      [ -f "$META_LOG" ] && [ -s "$META_LOG" ] && META='"="' || true
    else
      echo "[metadata] updated: $META previous: $PREV"
      PREV="$META"
      SHORT_PREV="${PREV:0:100}"
      [ "$SHORT_PREV" == "$PREV" ] || SHORT_PREV+=$'\t…'
    fi
    [ -z "$META_LOG" ] || (
      echo -ne '{\t'
      case "$META" in
        '"'?'"' ) printf '%s: %s\t}\n' "$META" "$NOW";;
        * ) printf '"@": %s,' "$NOW"; echo "${META#'{'}";;
      esac
      ) >>"$META_LOG" || true
    lurkrec_named_sleep log-helper "$INTV" || return 4$(
      echo E: $FUNCNAME: "Failed to sleep for '$INTV'" >&2)
  done
}


function lurkrec_file_growth_watchdog () {
  lurkrec_named_sleep watchdog-start 2m
  local TRACE='File growth watchdog:'
  local INTV_SEC=5
  local TOL_SEC="$WATCHDOG_WITH_ADS_TOL_SEC"
  echo -n D: $TRACE "Watching $REC_VIDEO_DEST for recorder $REC_PID "
  if [ -n "$SKIP_ADS" ]; then
    echo -n 'skipping ads'
    TOL_SEC="$WATCHDOG_SKIP_ADS_TOL_SEC"
  else
    echo -n 'including ads'
  fi
  echo " => tolerate $TOL_SEC consecutive seconds of file size stagnation." \
    "Will check every $INTV_SEC sec."

  local STREAK=0
  # We count our slept seconds ourselves rather than using $SECONDS, because
  # the time spent for non-sleep tasks could accumulate enough to cause timer
  # drift against $SECONDS, thus making the comparison trigger too-early.

  local PREV_SZ=0 SZ= DELTA=
  while lurkrec_named_sleep watchdog "$INTV_SEC"s; do
    if ! kill -0 "$REC_PID" 2>/dev/null; then
      echo D: $TRACE "Recorder seems to have quit."
      return 0
    fi
    SZ="$(stat --format %s -- "$REC_VIDEO_DEST")"
    [ -f "$REC_VIDEO_DEST" ] || return 4$(
      echo E: $TRACE: "File seems to have vanished: '$REC_VIDEO_DEST'" >&2)
    [ -n "$REC_VIDEO_DEST" ] || continue$(
      echo W: $TRACE: "Failed to detect file size of '$REC_VIDEO_DEST'" >&2)
    (( DELTA = SZ - PREV_SZ ))
    if [ "$DELTA" == 0 ]; then (( STREAK += INTV_SEC )); else STREAK=0; fi
    # echo D: $TRACE "+ $DELTA = $SZ streak $STREAK / $TOL_SEC"
    PREV_SZ="$SZ"
    [ "$STREAK" -le "$TOL_SEC" ] && continue
    echo W: $TRACE "Bark, bark!" >&2
    kill -HUP "$REC_PID"
    return 0
  done
}












lurkrec_cli_main "$@"; exit $?
