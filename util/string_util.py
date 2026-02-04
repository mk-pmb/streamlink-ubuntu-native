# -*- coding: UTF-8, tab-width: 4 -*-

import unicodedata


def snake_case(orig):
    buf = ''
    prev = '_'
    for ch in unicodedata.normalize('NFD', orig).lower():
        cat = unicodedata.category(ch)
        if cat == 'Mn': continue
        if not ch.isalnum():
            ch = '_'
        if ch == '_':
            if prev == ch: continue
        buf += ch
        prev = ch
    buf = buf.strip('_')
    return buf





# scroll
