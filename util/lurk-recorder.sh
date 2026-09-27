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
  local LOGF_FD=
  exec {LOGF_FD}</dev/null # just find the next unused FD.

  local NAMED_SLEEP_PIPE= # To avoid accidentally inheriting that variable.

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

  local MAIN_PID="$BASHPID"
  local PROXY_PROG=
  local SL_PROG_NAME='streamlink'
  local LURK_INTERVAL=15m
  local METADATA_INTERVAL=
  local FAIL_STREAM_DURA_SEC=180
  # ^-- Very short stream = probably just a glitch = retry sooner than usual
  local FAIL_STREAM_RETRY_DELAY=30s
  local FAIL_STREAM_MAX_RETRYS=10
  local WATCHDOG_INIT_DELAY=2m
  local WATCHDOG_DEFAULT_INTV_SEC=5
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
  local WAIT_NAME="$1"; shift
  local WAIT_TIME="$1"; shift

  local VAL="$WAIT_TIME"
  VAL="${VAL/%w/*7d}"
  VAL="${VAL/%d/*24h}"
  VAL="${VAL/%h/*60m}"
  VAL="${VAL/%m/*60}"
  VAL="${VAL%s}"
  let VAL=0 VAL="$VAL"
  [ "$VAL" -ge 1 ] || return 4$(
    echo E: $FUNCNAME: "$WAIT_NAME: Unsupported time format: '$WAIT_TIME'" >&2)
  WAIT_TIME="$VAL"

  local WAIT_IN_FD=
  exec {WAIT_IN_FD}> >(
    # Forking as I/O redirect makes the shell ignore the exit status of the
    # child process, i.e. not print the signal name. We could also achive
    # that with `disown`, but then we couldn't `wait`. Or we could force a
    # double subshell, but that would create two heavy forks of our process.

    exec 5<&0
    [ -z "$NAMED_SLEEP_PIPE" ] || exec 5<"$NAMED_SLEEP_PIPE"
    # Usually we have the named sleeper read from stdin and make that a
    # pipe for which we hold write access, effectively blocking it until
    # the timeout is reached, an overly complicated way to just sleep.
    # The benefit is that we can easily switch to waiting for any other
    # pipe instead, allowing the other side to wake us at any time.
    # Most importantly, we'll wake as soon as the last pipe-writer dies.
    #
    # We supply the read command via the input pipe in order to achieve
    # a clean-looking command line in the process list.
    exec -a "twrec-lurk-$WAIT_NAME-wait" bash
    )
  [ -n "$WAIT_IN_FD" ] || return 4$(
    echo E: $FUNCNAME: "$WAIT_NAME: Failed to fork!" >&2)
  echo "IFS= read -t $WAIT_TIME"' -u 5; exit $?' >&"$WAIT_IN_FD"
  wait $!
  local WAIT_RV=$?
  eval "exec $WAIT_IN_FD<&-"
  if [ "$WAIT_RV" -ge 128 ]; then
    # echo D: $FUNCNAME: "$WAIT_NAME: timeout."
    return 0
  fi
  # echo W: $FUNCNAME: "$WAIT_NAME: failed early: rv=$WAIT_RV" >&2
  return $WAIT_RV
}


function lurkrec_record () {
  [ "$$" == "$BASHPID" ] && [ "$$" == "$MAIN_PID" ] || return 4$(
    echo E: $FUNCNAME: 'Unexpected invocation by exotic control flow!' >&2)

  lurkrec_validate_weekdays_option || return $?
  # ^-- Fatal because syntax error in schedule is unrecoverable:
  #   We'll never (in this run) know whether at that moment we're allowed
  #   to bother the stream servers and/or use the credentials that may be
  #   set in the streamlink config.

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
        printf -- '%(%H%M%S)T' "$CHECK_UTS")-$MAIN_PID.txt"
      echo D: "Switching to new logfile: $LOGF_CUR"
      exec >>"$LOGF_CUR"
      eval "exec $LOGF_FD>&1"
      # eval "echo D: 'Switching to new logfile: New FDs:' >&$ORIG_STDOUT_FD"
      eval "ls -al -- /proc/$MAIN_PID/fd/ >&$ORIG_STDOUT_FD"
      exec &> >(exec "$SELFPATH"/logtee.sh "/proc/$MAIN_PID/fd/$LOGF_FD" \
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
  local REC_ALIVE_PIPE=4
  >"$REC_VIDEO_DEST" || return $?$(
    echo E: "Failed to record: Cannot create file: $REC_VIDEO_DEST" >&2)
  ( # Unfortunately bash doesn't expand variables in the FD number slot
    # of the redirect notation, so we need an eval here:
    eval "exec $REC_ALIVE_PIPE<> <(:)"
    exec "${REC_CMD[@]}" >"$REC_VIDEO_DEST"
  ) &
  local REC_PID=$!
  REC_ALIVE_PIPE="/proc/$REC_PID/fd/$REC_ALIVE_PIPE"
  local NAMED_SLEEP_PIPE="$REC_ALIVE_PIPE"
  local TRACE="Recording attempt $REC_PID:"

  : >(lurkrec_metadata_log_helper)
  local META_LOG_PID="$!"

  : >(lurkrec_file_growth_watchdog)
  local WATCHDOG_PID="$!"

  wait "$REC_PID"; local REC_RV=$?

  echo D: $TRACE "Wait for watchdog to quit: pid $WATCHDOG_PID"
  wait "$WATCHDOG_PID"
  echo D: $TRACE "Wait for meta logger to quit: pid $META_LOG_PID"
  wait "$META_LOG_PID"

  echo D: $TRACE "Done, rv=$REC_RV."
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

  local META_LOG_DEST_FILE="$REC_BFN"
  [ -z "$META_LOG_DEST_FILE" ] || META_LOG_DEST_FILE+='.meta.jsonl'
  exec 5<&-
  local META_LOG_DEST_LINK='/proc/self/fd/5'
  # Writing by file descriptor makes it so we can follow file renames.

  while kill -0 -- "$REC_PID" 2>/dev/null ; do
    META="$(lurkrec_metadata)"
    NOW="$EPOCHSECONDS"
    [ -z "$META_LOG_DEST_FILE" ] || [ -f "$META_LOG_DEST_LINK" ] ||
      exec 5>>"$META_LOG_DEST_FILE"
    if [ -z "$META" ]; then
      echo "[metadata] error! previous: $SHORT_PREV"
      META='"!"'
    elif [ "$META" == "$PREV" ]; then
      echo "[metadata] same: $SHORT_PREV"
      # Write "=" shorthand only if the current output file already has data:
      [ -f "$META_LOG_DEST_LINK" ] && [ -s "$META_LOG_DEST_LINK" ] &&
        META='"="' || true
    else
      echo "[metadata] updated: $META previous: $PREV"
      PREV="$META"
      SHORT_PREV="${PREV:0:100}"
      [ "$SHORT_PREV" == "$PREV" ] || SHORT_PREV+=$'\t…'
    fi
    [ -z "$META_LOG_DEST_FILE" ] || (
      echo -ne '{\t'
      case "$META" in
        '"'?'"' ) printf '%s: %s\t}\n' "$META" "$NOW";;
        * ) printf '"@": %s,' "$NOW"; echo "${META#'{'}";;
      esac
      ) >&5 || true
    lurkrec_named_sleep log-helper "$INTV" || return 4$(
      echo E: $FUNCNAME: "Failed to sleep for '$INTV'" >&2)
  done
  exec 5<&-
}


function lurkrec_file_growth_watchdog () {
  local WATCHDOG_PID="$BASHPID"
  local TRACE="File growth watchdog (pid $WATCHDOG_PID):"

  exec <"$REC_VIDEO_DEST" || return 4$(
    echo E: $TRACE 'Failed to obtain persistent file handle!' >&2)
  local REC_VIDEO_DEST='<BUG: mistakenly using filename instead of stdin>'
  local REC_DEST_LINK='/proc/self/fd/0'
  local REC_DEST_ABSDIR="$(readlink -m -- "$REC_DEST_LINK"/..)"
  local TAPE_NAME=
  lurkrec_file_growth_watchdog__check_tape_name || true

  if ! lurkrec_named_sleep watchdog-init $WATCHDOG_INIT_DELAY ; then
    echo D: $TRACE "Recorder $REC_PID vanished early."
    return 0
  fi
  lurkrec_file_growth_watchdog__check_tape_name || true

  local INTV_SEC="$WATCHDOG_DEFAULT_INTV_SEC"
  local TOL_SEC="$WATCHDOG_WITH_ADS_TOL_SEC"
  echo -n D: $TRACE "Watching '$TAPE_NAME' for recorder $REC_PID "
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
      echo D: $TRACE 'Recorder seems to have quit.'
      return 0
    fi
    lurkrec_file_growth_watchdog__check_tape_name || true
    SZ="$(stat --dereference --format %s -- "$REC_DEST_LINK")"
    [ -f "$REC_DEST_LINK" ] || return 4$(
      echo E: $TRACE 'Our tape seems to have been ejected.' >&2)
    [ -n "$SZ" ] || continue$(
      echo W: $TRACE 'Failed to measure tape position!' >&2)
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


function lurkrec_file_growth_watchdog__check_tape_name () {
  # Unfortunately, when `stat` applies `--dereference`,
  # it cannot print the resolved path, so we need two lookups.
  # We check the tape name first because this observation may be helpful
  # to debug why stat may have failed.
  local OLD="$TAPE_NAME"
  local UPD="$(readlink -- "$REC_DEST_LINK")"
  UPD="${UPD#$REC_DEST_ABSDIR/}"
  [ "$UPD" != "$OLD" ] || return 0
  [ -z "$OLD" ] ||
    echo D: $TRACE "Our tape has been renamed from '$OLD' to '$UPD'."
  TAPE_NAME="$UPD"
}












lurkrec_cli_main "$@"; exit $?
