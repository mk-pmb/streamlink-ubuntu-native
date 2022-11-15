#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function cli_main () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  local SELFPATH="$(readlink -m -- "$BASH_SOURCE"/..)"
  cd -- "$SELFPATH" || return $?

  local -A PKG_DB=()
  reg_pkg requests '
    ver   : 2.28.1
    blake2: a561a867851fd5ab77277495a8709ddda0861b28163c4613b011bc00228cc724
    sha256: 7c5599b102feddaa661c826c56ab4fee28bfd17f5abca1ebbe3e7f19d7c97983
    ' || return $?
  reg_pkg urllib3 '
    ver   : 1.26.12
    blake2: b256d87d6d3c4121c0bcec116919350ca05dc3afd2eeb7dc88d07e8083f8ea94
    sha256: 3fa96cf423e6987997fc326ae8df396db2a8b7c667747d47ddd8ecba91f4a74e
    libsub: src/
    ' || return $?

  install_all_pkgs || return $?
}


function install_all_pkgs () {
  local PKG=
  for PKG in ${PKG_DB[:names]}; do
    install_one_pkg "$PKG" || return $?
  done
  [ -d tmp ] && echo "You may optionally remove this directory: $SELFPATH/tmp"
  echo "All done. Good luck!"
}


function reg_pkg () {
  local PKG_NAME="$1" PKG_DATA="$2"
  PKG_DB[:names]="$(<<<"${PKG_DB[:names]}"$'\n'"$PKG_NAME" grep . | sort -Vu)"
  local KEY= VAL=
  while [ -n "$PKG_DATA" ]; do
    case "$PKG_DATA" in
      ' '* | $'\n'* ) PKG_DATA="${PKG_DATA:1}"; continue;;
      *': '* )
        VAL="${PKG_DATA%%$'\n'*}"
        PKG_DATA="${PKG_DATA#*$'\n'}"
        KEY="${VAL%%: *}"
        KEY="${KEY// /}"
        VAL="${VAL#*: }"
        PKG_DB["$PKG_NAME:$KEY"]="$VAL"
        ;;
      * ) echo "E: Syntax error in PKG_DATA" >&2; return 4;;
    esac
  done
}


function install_one_pkg () {
  local PKG_NAME="$1"
  local INIT_PY="lib/$PKG_NAME/__init__.py"
  if [ -f "$INIT_PY" ]; then
    echo "Package $PKG_NAME: found. skip."
    return 0
  fi

  mkdir --parents tmp || return $?
  local DL_URL="https://files.pythonhosted.org/packages/"
  local HASH_PATH="${PKG_DB[$PKG_NAME:blake2]}"
  DL_URL+="${HASH_PATH:0:2}/"
  DL_URL+="${HASH_PATH:2:2}/"
  DL_URL+="${HASH_PATH:4}/"
  local DL_BFN="$PKG_NAME-${PKG_DB[$PKG_NAME:ver]}.tar.gz"
  DL_URL+="$DL_BFN"
  local DL_DEST="tmp/$DL_BFN"

  install_one_pkg__download || return $?
  install_one_pkg__verify || return $?
  install_one_pkg__unpack || return $?
}


function install_one_pkg__download () {
  local DL_PART="$DL_DEST.part"
  [ -s "$DL_DEST" ] && return 0

  echo "Package $PKG_NAME: Download $DL_PART <- $DL_URL"
  wget --output-document "$DL_PART" --continue --no-clobber \
    -- "$DL_URL" || return $?
  mv --verbose --no-target-directory -- "$DL_PART" "$DL_DEST" || return $?
  echo
}


function install_one_pkg__verify () {
  echo -n "Package $PKG_NAME: Verify integrity: "
  local HASH= WANT= FOUND=
  for HASH in sha256; do
    WANT="${PKG_DB[$PKG_NAME:$HASH]}"
    FOUND="$("$HASH"sum --binary -- "$DL_DEST")"
    FOUND="${FOUND%% *}"
    if [ "$FOUND" == "$WANT" ]; then
      echo -n "$HASH ok, "
    else
      echo "$HASH differs!"
      echo "D: File on disk: $HASH = $FOUND" >&2
      echo "D: Expected:     $HASH = $WANT" >&2
      echo "E: Downloaded file has wrong $HASH checksum!" >&2
      return 71
    fi
  done
  echo "seems legit."
}


function install_one_pkg__unpack () {
  echo -n "Package $PKG_NAME: Unpack: "
  local DL_BFN=".tar.gz"
  local SUB="$PKG_NAME-${PKG_DB[$PKG_NAME:ver]}/"
  SUB+="${PKG_DB[$PKG_NAME:libsub]}"
  SUB+="$PKG_NAME"
  tar --directory=tmp --extract --gzip --file "$DL_DEST" -- "$SUB" || return $?
  mkdir --parents lib || return $?
  mv --verbose --target-directory=lib -- tmp/"$SUB" || return $?
}










cli_main "$@"; exit $?
