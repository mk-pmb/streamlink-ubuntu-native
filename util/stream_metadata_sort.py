#!/usr/bin/python3
# -*- coding: UTF-8, tab-width: 4 -*-

import json
import re
import sys

priority_keys = {
    "category": None,
    "title": None,
}

data = json.load(sys.stdin)
data = data.get('metadata', data)
data = dict(sorted(data.items()))
data = { **priority_keys, **data }
data = json.dumps(data, indent=0, ensure_ascii=False)

def to_unicode_hex_escape(char):
    if hasattr(char, 'group'):
        char = char.group(0)
    return f'\\u{ord(char):04x}'

data = re.sub(r'[\x00-\t\v-\x1F]', to_unicode_hex_escape, data)

print(data)
