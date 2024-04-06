#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function twitch_transcode_live () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local REPO_DIR="$(readlink -m -- "$BASH_SOURCE"/../..)"
  # cd -- "$REPO_DIR" || return $?

  local -A OUT=(
    [dest]='<chan>/<p>/'
    [p]=360   # height in pixels, named "p" because of 360p, 480p etc.
    [fps]=30

    [crf]=25
    # ^-- Constant Rate Factor. lower value = better quality = larger file.

    [kbps]=600
    # ^-- Twitch's transcoder seems to use 600 to 700 kbps for 360p.
    )

  local CHAN="$1"; shift
  CHAN="${CHAN%/}"

  local RECV_QUALI='worst'
  # ^-- Works since this script is meant to be used for streams that don't
  #     have transcoding available. However, you could still adjust:
  case "$CHAN" in
    *@[0-9]* | *@best | *@worst )
      [ -d "$CHAN" ] && OUT[dest]="$CHAN/"
      RECV_QUALI="${CHAN#*@}"
      CHAN="${CHAN%%@*}"
      RECV_QUALI="${RECV_QUALI%p}"
      ;;
  esac
  [ -n "$CHAN" ] || return 4$(echo E: 'No channel name given!' >&2)
  [[ "$CHAN" == *[A-Za-z]* ]] || return 4$(
    echo E: 'Channel name has no letters in it.' >&2)
  [[ "$CHAN" == [A-Za-z0-9]* ]] || return 4$(
    echo E: 'Channel name must start with a letter or number.' >&2)
  local SUS="${CHAN//[A-Za-z0-9-]/}"
  SUS="${SUS/,/}"
  [ -z "$SUS" ] || return 6$(
    echo E: "Suspicious characters in channel name: '$SUS'" >&2)

  OUT[dest]="${OUT[dest]//<chan>/$CHAN}"
  OUT[dest]="${OUT[dest]//<rcvQ>/$RECV_QUALI}"
  OUT[dest]="${OUT[dest]//<p>/${OUT[p]}}"
  [ -d "${OUT[dest]}" ] || return 4$(
    echo E: "Output destination is not a directory: ${OUT[dest]}" >&2)

  [ "${CHAN/,/}" == "$CHAN" ] || CHAN="${CHAN#*,}${CHAN%%,*}"

  local KEY= VAL= AUX=
  while [ "$#" -ge 1 ]; do
    VAL="$1"; shift
    case "$VAL" in
      [a-z]*=* )
        KEY="${VAL%%=*}"
        [ -n "${OUT[$KEY]}" ] || return 6$(
          echo E: "Unknown option '$KEY=…'." >&2)
        VAL="${VAL#*=}"
        case "$KEY" in
          dest | \
          =string=keys= ) ;;
          * ) # numbers
            AUX=0
            let AUX="$VAL"
            [ "$AUX" -ge 1 ] || return 6$(
              echo E: "Expected a positive number for option '$KEY'." >&2)
            VAL="$AUX"
            ;;
        esac
        OUT["$KEY"]="$VAL"
        ;;
    esac
  done

  find "${OUT[dest]}" -mindepth 1 -maxdepth 1 -regextype egrep \
    -regex '^.*/(init|chunk)-stream[0-9-]*\.m4s(|\.tmp)$' \
    -delete || true

  local DEST_BASEDIR_RGX="$(
    <<<"${OUT[dest]}" sed -re 's~[^A-Za-z0-9_/-]~\\&~g')"

  # OUT[dest]+='_live.mpd' # DASH
  OUT[dest]+='_.m3u8' # HLS

  local RECV_OPT=(
    # --ringbuffer-size 4K
    --twitch-disable-hosting
    --twitch-disable-reruns
    --stream-url
    twitch.tv/"$CHAN"
    "$RECV_QUALI"
    )

  echo P: "Trying to detect stream URL…"
  local RECV_URL="$( "$REPO_DIR"/wrapper.sh "${RECV_OPT[@]}" )"
  [ -n "$RECV_URL" ] || return 6$(echo E: 'Unable to detect stream URL!' >&2)
  echo P: "Stream URL detected as: $RECV_URL"

  local FIXUP_AD_SEGMENTS=(
    ffmpeg
    -i "$RECV_URL"
    -c copy -f mpegts -
    )
  local TRANSCODE=(
    ffmpeg
    -i -
    -vf "scale=-1:${OUT[p]},setsar=1:1"

    # Bitrate should be set before codecs, so the codecs can optimize for it.
    -b:v "${OUT[kbps]}k"

    -c:v libx264
    -profile:v main
    -preset medium
    -crf "${OUT[crf]}"
    -strict -2
    -r "${OUT[fps]}"
    )

  case "${OUT[dest]}" in
    *.mpd )
      TRANSCODE+=(
        -c:a aac
        # Unfortunately, dash seems to require that I re-encode the audio
        # from AAC to AAC with slightly different settings, so for now I'll
        # accept HLS's slighly worse stream delay.
        # An alternative would be to try
        #     -c:a copy -copy_unknown
        # but with that, ffmpeg complains:
        #     Could not find tag for codec aac in stream #0, codec not
        #     currently supported in container

        -f dash "${OUT[dest]}"
      );;

    *.m3u8 ) TRANSCODE+=( -c:a copy  -f hls  "${OUT[dest]}" );;
  esac

  # exec > >(tee -- "${OUT[dest]}".log)
  ( "${FIXUP_AD_SEGMENTS[@]}" | "${TRANSCODE[@]}"
    echo D: "ffmpeg ${TRANSCODE[*]}"
  ) |& tr '\r' '\n' | sed -ure "s|$DEST_BASEDIR_RGX|/var/www/stream/|g" \
    -f "$REPO_DIR"/util/unclutter_twitch_ffmpeg_logs.sed
}






twitch_transcode_live "$@"; exit $?
