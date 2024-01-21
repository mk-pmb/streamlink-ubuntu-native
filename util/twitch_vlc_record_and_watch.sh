#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function twrec_cli () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  # cd -- "$SELFPATH" || return $?
  local DBGLV="${DEBUGLEVEL:-0}"

  local -A CFG=(

    [default_channel]=''
    [quality]='360p'
    [fallback_quality]='worst'
    [bufsz_kb]=4
    # 2021-04-08: 480p ≈ ca. 200 KB/sec
    [vlc_volume_down_key]='Down'

    [dest_pre]=''
    [core_delay]=''
    [dest_suf]='.rec.tmp'
    [dest_ext]='.mp4'

    [adblock]='--twitch-disable-ads'

    )

  local DOT_DIR_NAME='.twrec'
  local TASK='rec'
  local OPT= VAL=
  local PRE_ARGS=()
  while [ "$#" -ge 1 ]; do
    OPT="$1"; shift
    case "$OPT" in
      -- ) break;;
      --func ) "$@"; return $?;;

      @audio ) CFG[quality]="${OPT#\@}_only";;
      @best | \
      @worst | \
      @[0-9][0-9]* )
        OPT="${OPT#\@}"
        OPT="${OPT%p}"
        case "$OPT" in
          *p ) ;;
          [0-9]*p[0-9]* ) ;;
          [0-9]* ) OPT+='p';;
        esac
        CFG[quality]="$OPT"
        ;;

      -r ) TASK='rec';;
      -c ) TASK='cleanup_tmps';;
      -d ) CFG[core_delay]="$1"; shift;;
      -l | --lurk ) CFG[lurk_interval]="$1"; shift;;
      -b ) CFG[bufsz_kb]="$1"; shift;;
      --ads ) CFG[adblock]=;;

      --debug ) let DBGLV="$DBGLV+1";;
      --debug=* ) DBGLV="${OPT#*=}";;
      --summarize-config | \
      --cleanup-tmps | \
      _ )
        TASK="${OPT//-/_}"
        TASK="${TASK#_}"
        TASK="${TASK#_}"
        ;;

      --*=* )
        VAL="${OPT#*=}"
        OPT="${OPT%%=*}"
        OPT="${OPT#--}"
        OPT="${OPT//-/_}"
        CFG["$OPT"]="$VAL";;

      -* )
        echo "E: unsupported option '$OPT'." \
          "If it was meant as a streamlink option, separate it with '--'." >&2
        return 8;;

      * ) PRE_ARGS+=( "$OPT" ); break;;
    esac
  done

  twrec_"$TASK" "${PRE_ARGS[@]}" "$@"; return $?
}


function str_repeat () {
  local BUF=
  printf -v BUF '% *s' "$1" ''
  echo -n "${BUF// /"$2"}"
}


function twrec_rec () {
  local CHAN_DIR="$1"; shift
  CHAN_DIR="${CHAN_DIR%/}"
  [ -n "$CHAN_DIR" ] || CHAN_DIR="${CFG[default_channel]}"
  [ -n "$CHAN_DIR" ] || return 4$(echo E: 'No channel name given.' >&2)
  [ -n "$QUALI" ] || case "$CHAN_DIR" in
    *@* ) QUALI="${CHAN_DIR##*@}"; CHAN_DIR="${CHAN_DIR%@*}";;
  esac
  [ -n "$QUALI" ] || QUALI="${CFG[quality]}"

  local CHAN_SLUG="$(canonical_channel_name "$CHAN_DIR")"
  [ -n "$CHAN_SLUG" ] || return 3$(echo "E: cannot guess channel URL slug" >&2)

  [ -d "${CHAN_DIR}@${QUALI}" ] && CHAN_DIR+="@$QUALI"
  expect_local_fs || return $?
  local CREATED_CHAN_DIR=
  if [ ! -d "$CHAN_DIR" ]; then
    mkdir --parents -- "$CHAN_DIR" || return $?
    CREATED_CHAN_DIR=+
  fi

  if [ -n "${CFG[lurk_interval]}" ]; then
    twrec_stubbornly_retry_every "${CFG[lurk_interval]}" \
      twrec_rec_core "$@"; return $?
  fi

  local CORE_RV=
  SECONDS=0
  twrec_rec_core "$@"; CORE_RV=$?

  maybe_remove_freshly_created_chan_dir

  return "$CORE_RV"
}


function maybe_remove_freshly_created_chan_dir () {
  # Maybe remove freshly created chan dir on quick failure, assuming the
  # channel name was mistyped:

  [ -n "$CREATED_CHAN_DIR" ] || return 0
  [ "$CORE_RV" == 0 ] && return 0
  [ "$SECONDS" -lt 30 ] || return 0
  rmdir --verbose -- "$CHAN_DIR" || return $?
}


function twrec_rec_core () {
  local REC_DEST="$CHAN_DIR/${CFG[dest_pre]}"$(
    )"%%<date_time>%%${CFG[dest_suf]}${CFG[dest_ext]}"

  local EFF_QUALI="$QUALI,${CFG[fallback_quality]}"
  EFF_QUALI="${EFF_QUALI%,}"

  local SL_CMD=(
    streamlink
    --ringbuffer-size "${CFG[bufsz_kb]}"K
    --twitch-disable-hosting
    ${CFG[adblock]}
    --twitch-disable-reruns
    # --twitch-api-header Client-ID=ue6666qo983tsx6so1t0vnawi233wa
    # --twitch-low-latency
    --stdout

    --title '{author}: {category}: {title}'
    # ^-- Unfortunately, the title information doesn't survive our
    #     mpegts conversion.
    )

  local TOKEN="$(read_channel_oauth_token)"
  if [ -n "$TOKEN" ]; then
    TOKEN="${#SL_CMD[@]} --twitch-api-header=Authorization=OAuth $TOKEN"
    SL_CMD+=( '%%<oauth_token>%%' )
  fi

  SL_CMD+=(
    "$@"

    twitch.tv/"$CHAN_SLUG"
    "$EFF_QUALI"
    )
  echo "D: $(twrec_summarize_config | tr -s '\n ' ' ')-> $REC_DEST"
  [ "$DBGLV" -lt 2 ] || echo "D: Effective command: ${SL_CMD[*]}" >&2
  if [ -n "${CFG[core_delay]}" ]; then
    printf -- 'D: core delay start: %(%F %T)T, delay: %s\n' \
      -1 "${CFG[core_delay]}"
    sleep "${CFG[core_delay]}" || return $?
    printf -- 'D: core delay end  : %(%F %T)T\n' -1
  fi

  # Now that the core delay has elapsed, we can insert into the filename
  # the correct date/time or start of recording.
  local REC_START=
  printf -v REC_START -- '%(%y%m%d-%H%M%S)T' -1
  REC_DEST="${REC_DEST//%%<date_time>%%/$REC_START}"
  echo "D: Effective recording filename with date and time: $REC_DEST"

  [ -z "$TOKEN" ] || SL_CMD["${TOKEN%% *}"]="${TOKEN#* }"

  local VLC_TITLE="Twitch >> $REC_DEST"
  local VLC_CMD=(
    vlc
    --no-one-instance
    --play-and-exit

    --meta-title "$VLC_TITLE"
    # ^-- Unfortunately, VLC will only honor --meta-title once the playback
    #     actually starts. While waiting for that, it will show "fd://0" as
    #     the title. I tried mitigating this by giving `very_short_silence.au`
    #     as first playback item, but VLC changed the title back to "fd://0"
    #     once it had played the au file.

    # --qt-minimal-view
    - )

  exec 8> >( exec "${VLC_CMD[@]}" &>/dev/null )
  local VLC_PID=$!
  [ "$DBGLV" -lt 2 ] || echo "D: VLC pid: $VLC_PID" >&2

  xdolurk_all &

  local HAD_ANY_MEDIA_BYTES=
  local PIPE_CMD='"${SL_CMD[@]}"'

  local UNBUFFERED='stdbuf -i0 -o0 -e0'
  local BEST_LOG_TIMESTAMPER="$(which \
    timecat \
    ts \
    2>/dev/null | grep -m 1 -Pe '^/')"
  [ -x "$BEST_LOG_TIMESTAMPER" ] && PIPE_CMD+=' 2> >(
    $UNBUFFERED "$BEST_LOG_TIMESTAMPER" >&2)'

  local CONV_MPEGTS=(
    ffmpeg
    -i -
    -loglevel warning
    -c copy
    # -f mpegts   # unfortunately, VLC cannot seek properly inside MPEGTS.
    )
  case "$REC_DEST" in
    *.mpegts | *.ts ) PIPE_CMD+=' | "${CONV_MPEGTS[@]}" -f mpegts -';;
  esac

  PIPE_CMD+=' | $UNBUFFERED tee -- "$REC_DEST"'
  # ^-- In theory, we could use --record-and-pipe for cases where we don't
  #     need a conversion step. However, for that we'd have to replace
  #     --stdout with two items, or have to decide the conversion before
  #     we define SL_CMD. I tried and the logic for that turned out more
  #     of a hassle than it's worth.

  twrec_inject_clip before >&8 || true
  eval "$PIPE_CMD" >&8
  local SL_PIPE_RV="${PIPESTATUS[*]}"
  let SL_PIPE_RV="${SL_PIPE_RV// /+}"

  if [ -s "$REC_DEST" ]; then
    HAD_ANY_MEDIA_BYTES=+
  else
    rm -- "$REC_DEST" || true
  fi

  if [ "$SL_PIPE_RV" == 0 ]; then
    twrec_inject_clip after >&8 || true
  else
    twrec_inject_clip failed >&8 || true
  fi
  twrec_vlc_fallback_dummy_media >&8 || true

  return "$SL_PIPE_RV"
}


function twrec_stubbornly_retry_every () {
  local INTV="$1"; shift
  while true; do
    "$@" && return 0
    printf '%(%F %T)T %s\n' -1 \
      "E: failed (rv=$?), will retry in $INTV: $*"
    sleep "$INTV" || return $?
  done
}


function canonical_channel_name () {
  local CH="$1"
  CH="${CH%/}"    # for convenience of --func debugging
  CH="${CH%%@*}"
  CH="${CH,,}"
  local ERR="E: $FUNCNAME:"

  case "$CH" in
    *[^A-Za-z0-9,_-]* )
      echo "$ERR scary character(s) in channel directory name" >&2
      return 3;;
  esac

  [[ "$CH" == *,* ]] && CH="${CH#*,}${CH%,*}"
  [[ "$CH" == *,* ]] && return 3$(echo "$ERR multiple commas: $CH" >&2)

  echo "$CH"
}


function expect_local_fs () {
  df --local . >/dev/null || return 4$(
    echo "E: flinching from operating on a remote filesystem" >&2)
}


function twrec_cleanup_tmps () {
  expect_local_fs || return $?
  local ACTIVE=$'\n'"$(
    ps ho args -C streamlink | grep -oPe ' --record \S+ ' | cut -d ' ' -sf 3
    ps ho args -C tee | sed -nre 's!^tee -- !!;/\s/!p'
    )"$'\n'
  local PRE="${CFG[dest_pre]}"
  local SUF="${CFG[dest_suf]}"
  local ITEM=" $PRE $SUF "
  ITEM="${ITEM//[^A-Za-z0-9]/ }"
  case "$ITEM" in
    *' tmp '* ) ;;
    * )
      echo "W: $FUNCNAME: neither prefix nor suffix contains 'tmp'"\
        "or a similar keyword => flinch from auto-deleting files." >&2
      return 0;;
  esac
  for ITEM in */"$PRE"*"$SUF${CFG[dest_ext]}"; do
    [ -f "$ITEM" ] || continue
    if [[ "$ACTIVE" == *$'\n'"$ITEM"$'\n'* ]]; then
      echo "active, keep: $ITEM"
      continue
    fi
    rm --verbose -- "$ITEM"
  done
}


function twrec_summarize_config () {
  local SORT='env LANG=C sort --version-sort'
  echo 'env:'
  env | grep -Pie '^\w+_proxy=' | $SORT

  echo 'cfg:'
  local KEY=
  for KEY in "${!CFG[@]}"; do echo "$KEY=‹${CFG[$KEY]}›"; done | $SORT
}


function twrec_inject_clip () {
  local QUALI="${EFF_QUALI:-$QUALI}"
  QUALI="${QUALI%%,*}"

  # Tested 2023-07-25: VLC v3.0.9.2 supports concatenating multiple MPEGTS
  #   stream fragments with varying image size, and will adapt its window
  #   if zoom is set to fixed-percentage and window-resizing is enabled.
  #   Therefor, choosing a wrong preroll resolution may subvert users'
  #   early attempts to arrange the window position.

  # Tested 2023-07-26: Unfortunately, VLC v3.0.9.2 seems to not support
  #   arbitrary changes in audio codecs. Thus, prerolls have to be from a
  #   compatible stream, which usually means from the same streamer.

  local PATH_TEMPLATES=(
    "<<chan>>/$DOT_DIR_NAME/inject/<<event>>.@<<quali>>.mpegts"
    "$DOT_DIR_NAME/inject/<<chan>>/<<event>>.@<<quali>>.mpegts"
    )

  local QUALI="$QUALI"
  local CHAN_DIR="$CHAN_DIR"
  local EVENT=
  local ITEM=
  for CHAN_DIR in "$CHAN_DIR" all; do
    for EVENT in "$@"; do
      for QUALI in "$QUALI" 360p any; do
        for ITEM in "${PATH_TEMPLATES[@]}"; do
          ITEM="${ITEM//<<chan>>/$CHAN_DIR}"
          ITEM="${ITEM//<<event>>/$EVENT}"
          ITEM="${ITEM//<<quali>>/$QUALI}"
          if [ -f "$ITEM" ]; then
            if [ -s "$ITEM" ]; then
              echo "D: inject: $ITEM" >&2
              cat -- "$ITEM" || return $?
              HAD_ANY_MEDIA_BYTES=+
            else
              # Empty file can be used to opt-out of a default file
              # that would have been found later.
              [ "$DBGLV" -lt 8 ] || echo "D: inject empty: $ITEM" >&2
            fi
            return 0
          elif [ "$DBGLV" -ge 8 ]; then
            echo "D: inject not found: $ITEM" >&2
          fi
        done # ITEM
      done # QUALI
    done # EVENT
  done # CHAN_DIR
  [ "$DBGLV" -lt 2 ] || echo "D: inject found none for event(s): $*" >&2
  return 3
}


function twrec_vlc_fallback_dummy_media () {
  # When no stream data can be received, usually, VLC's input would close
  # with no data at all. In that case, VLC will display an error message
  # about invalid video format. To avoid that useless message, we can play
  # a very short dummy media file.

  # Unfortunately, our pipe to VLC will always report "pos: 0" in
  # /proc/self/fdinfo/8 as well as /proc/$VLC_PID/fdinfo/0 even after
  # sending several kilobytes.
  # We thus have to rely on our earlier size check on our recording file:

  if [ -n "$HAD_ANY_MEDIA_BYTES" ]; then
    [ "$DBGLV" -lt 2 ] \
      || echo "D: $FUNCNAME: We seem to have sent some bytes." >&2
    return 0
  fi

  [ "$DBGLV" -lt 2 ] || echo "D: $FUNCNAME: sending." >&2
  cat -- "$SELFPATH"/very_short_silence.au
}


function read_channel_oauth_token () {
  local CANDIDATES=(
    "$CHAN_DIR/$DOT_DIR_NAME/auth-token-cookie.txt"
    "$CHAN_DIR/.auth-token-cookie.txt"
    )
  local SRC= VAL=
  for SRC in "${CANDIDATES[@]}"; do
    VAL="$([ -r "$SRC" ] && grep -m 1 -xPe '\w\S*' -- "$SRC")"
    VAL="${VAL#auth-token=}"
    [ -n "$VAL" ] || continue
    [ "$DBGLV" -lt 2 ] || echo "D: OAuth token: ${#VAL} bytes from $SRC" >&2
    echo "$VAL"
    return 0
  done
  [ "$DBGLV" -lt 2 ] || echo "D: No OAuth token in any of" \
    "${CANDIDATES[*]} (cwd is $PWD)" >&2
  return 4
}


function find_vlc_window () {
  [ "${VLC_PID:-0}" -ge 1 ] || return 4$(echo E: >&2 $FUNCNAME: \
    "Expected VLC_PID to be a positive number, not '$VLC_PID'.")
  local TIMEOUT_SEC=5
  # echo D: $FUNCNAME: "Trying to find VLC window: PID $VLC_PID" >&2
  local VLC_WIN_ID="$(xdocool find_winid_by_pid "$VLC_PID" "$TIMEOUT_SEC")"
  [ -n "$VLC_WIN_ID" ] || return 4$(echo E: >&2 $FUNCNAME: \
    "Failed to find window ID for PID '$VLC_PID'.")
  # echo D: $FUNCNAME: "Found VLC window: ID $VLC_WIN_ID" >&2
  echo "$VLC_WIN_ID"
}


function xdolurk_all () {
  local VLC_WIN_ID="$(find_vlc_window)"
  xdolurk_undisturb || return $?
  xdolurk_drive_down_volume || return $?
}


function xdolurk_undisturb () {
  # The idea of "undisturb" orininally was to minimize the new VLC window
  # so users can continue doing their stuff while waiting for the stream
  # to load. However, this won't achieve the desired effect, because VLC
  # will raise itself once the stream starts, interrupting the user's work
  # even worse. Also, when it was initially maximized and then raises itself,
  # it unmaximizes itself.
  # As a work-around, we hide the VLC window, check which other window was
  # active, then unhide VLC (i.e. restore its window to a state it deems
  # acceptable), then switch back to the previously active window.
  xdotool windowunmap --sync "$VLC_WIN_ID" || return $?
  sleep 0.1s
  local PREV_WIN="$(xdotool getactivewindow)"
  xdotool windowmap --sync "$VLC_WIN_ID" || return $?
  sleep 0.1s
  xdotool windowactivate "$PREV_WIN" || return $?
}


function xdolurk_drive_down_volume () {
  # We want all streams to start mute, so users can safely do other things
  # while waiting for the stream to start, and then later increase volume
  # once they have time to deal with that.
  #
  # This is especially useful for coping with Twitch's oh-so-funny pre-roll
  # jokes with the annoying music.
  #
  # ATTN: VLC v3.0.9.2 on Ubuntu with PulseAudio seems to initially lie
  #   about the volume, *always* showing it as zero while waiting for the
  #   stream to load. However, if left alone, volume will change as soon as
  #   the stream begins.
  #   Forum discussions about setting initial volume for VLC with PulseAudio
  #   say that VLC cannot directly set it; it seems that VLC can merely query
  #   it and adjust it relatively. (And it seems the devs have no intent on
  #   implementing a wait-compare-adjust loop for that.)
  #   Thus, my theory for what happens is that volume is set by PulseAudio
  #   as soon as VLC starts an actual output channel, and the volume changes
  #   we request via keystroke are queued up until the output channel is
  #   ready enough to process them. Fortunately, they seem to process so
  #   quickly that it's basically immediate.
  local KEY="${CFG[vlc_volume_down_key]}"
  [ -n "$KEY" ] || return 0
  xdotool key --window "$VLC_WIN_ID" --delay 20 $(str_repeat 50 "$KEY ")
  # echo D: $FUNCNAME: "Keys sent." >&2
}












twrec_cli "$@"; exit $?
