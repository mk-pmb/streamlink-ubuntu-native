#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-
set -e
VENV_DIR='venv'
export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
REPO_DIR="$(readlink -m -- "$BASH_SOURCE"/../..)"
cd -- "$REPO_DIR"
[ -d "$VENV_DIR" ] || python3 -m venv "$VENV_DIR"
./"$VENV_DIR"/bin/python3 -m ensurepip
./"$VENV_DIR"/bin/python3 -m pip install --upgrade -- pip sl-repo/
