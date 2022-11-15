# -*- coding: UTF-8, tab-width: 4 -*-

try:
    from Cryptodome.Util.Padding import (
        pad,
        unpad,
        )
except ModuleNotFoundError:
    pad = 'stub'
    unpad = 'stub'
