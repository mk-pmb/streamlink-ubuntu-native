#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-

# Please excuse the ugliness in this file.
# It's meant to cope with alpine linux.

inside_python_alpine () {
  HOME=/dtmp
  mkdir -p "$HOME" || return $?
  export HOME
  cd || return $?
  python3 -m venv venv || return $?
  . venv/bin/activate || return $?
  local SPKG=
  for SPKG in "$HOME"/venv/lib/python*/site-packages; do
    [ -d "$SPKG" ] && break || true
  done

  local PKG="$SPKG"/streamlink
  mkdir -p -- "$PKG" # to ensure our next glob pattern will match
  vdo rm -r -- "$PKG"*/ || return $?
  vdo cp -nrt "$SPKG" -- /sl-repo/src/streamlink*/ || return $?

  # Install shims for packages that don't work well with zipapp:
  vdo cp -rt "$SPKG" -- /shims/*/ || return $?

  vdo pip_install_list /app/acceptable_in_ubuntu.txt || return $?
  vdo pip_install_list /app/lacking_in_ubuntu.txt || return $?
  vdo pip_install_list /app/bundling_util.txt || return $?
  vdo python3 -m streamlink_cli --version || return $?

  # vdo prepare_bundle_of_upgrades || return $?
}


vdo () {
  echo
  echo ">>===>> $* >>===>>"
  local RV=
  "$@"; RV=$?
  if [ "$RV" = 0 ]; then
    echo "<<===<< $* <<===<< done <<===<<"
  else
    echo "<<===<< $* <<===<< error $RV <<===<<"
  fi
  return "$RV"
}


read_pkgnames () {
  grep -e '^[a-z]' -- "$1"
}


pip_install_list () {
  local PKG="$(echo $(read_pkgnames "$1") )"
  echo "packages: $PKG"
  for PKG in $PKG; do
    [ -d "$SPKG/$PKG" ] || vdo pip3 install "$PKG" || return $?
  done
}


prepare_bundle_of_upgrades () {
  local BUN="$HOME/upgrades"
  mkdir -p -- "$BUN" || return $?

  local INIT="$BUN"/__init__.py
  head -n 2 -- /app/zipper.py >"$INIT" || return $?

  local PKG=
  for PKG in $(read_pkgnames /app/lacking_in_ubuntu.txt); do
    echo "from . import $PKG" >>"$INIT" || return $?
    [ ! -L "$BUN/$PKG" ] || rm -- "$BUN/$PKG" || return $?
    ln -sT -- "$SPKG/$PKG" "$BUN/$PKG" || return $?
  done

  python3 /app/zipper.py "$HOME"/upgrades.pyz "$BUN" || return $?
  # shiv -o "$HOME"/upgrades.pyz "$BUN" || return $?
}























inside_python_alpine || exit $?
