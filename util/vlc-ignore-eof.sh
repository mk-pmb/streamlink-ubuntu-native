#!/bin/sh
# -*- coding: utf-8, tab-width: 2 -*-
ld-preload-autocompile-pmb --resolve-strip-suffix "$0" .sh vlc "$@"; exit $?
