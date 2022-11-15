#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function bake_cli_main () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  proxified_docker_build || return $?
}



function proxified_docker_build () {
  cd -- "$SELFPATH" || return $?

  local SL_REPO="$(readlink -m -- "$SELFPATH"/../..)/streamlink-repo"
  local CFG_FN= KEY= VAL=
  for CFG_FN in cfg.@"$HOSTNAME".rc; do
    [ ! -f "$CFG_FN" ] || source_in_func "$CFG_FN" || return $?
  done

  VAL="$SL_REPO"/src/streamlink/__main__.py
  if [ ! -f "$VAL" ]; then
    echo "E: Cannot find $VAL" >&2
    echo "H: Please arrange the following path to be either" \
      "your locally cloned streamlink repo, or a symlink to it: $SL_REPO" >&2
    return 4
  fi

  local DK_CMD=(
    docker
    run
    )

  local KEY= VAL=
  for KEY in http{,s}_proxy; do
    for KEY in "$KEY" "${KEY^^}"; do
      eval 'VAL=${'"$KEY"'}'
      [ -z "$VAL" ] || DK_CMD+=( --env "$KEY=$VAL" )
    done
  done

  if [ -d docker.tmp ]; then
    echo "W: Using a persistent docker.tmp directory!" \
      "This is meant for debugging only." \
      "If you're not sure you want this, please remove: $PWD/docker.tmp" >&2
    DK_CMD+=( --volume "$PWD/docker.tmp:/dtmp:rw" )
  fi

  DK_CMD+=(
    --volume "$SL_REPO:/sl-repo:ro"
    --volume "$PWD/inside:/app:ro"
    --volume "$PWD/../shims:/shims:ro"
    --workdir /app
    python:3.9-alpine
    /app/inside.sh
    )
  # local -p
  echo "D: bake cmd: ${DK_CMD[*]}"
  "${DK_CMD[@]}" || return $?
}


function source_in_func () {
  source -- "$1" || return $?$(echo "E: Failed to source $1" >&2)
}





bake_cli_main "$@"; exit $?
