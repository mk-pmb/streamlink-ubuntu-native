#!/usr/bin/python3
# -*- coding: UTF-8, tab-width: 4 -*-

import json
import re
import sys

import string_util


priority_keys = {
    'category_snake': None,
    'category': None,
    'title': None,
}

data = json.load(sys.stdin)
data = data.get('metadata', data)
data['category_snake'] = string_util.snake_case(data.get('category') or '')
data = dict(sorted(data.items()))
data = { **priority_keys, **data }

empty_string_fields = []
for k, v in data.items():
    if v == '':
        empty_string_fields += (k,)
if len(empty_string_fields):
    trace = ' <- detected by …/' + '/'.join(__file__.split('/')[-3:])
    empty_string_fields += (trace,)
    data['empty_string_fields'] = '|'.join(empty_string_fields)

data = json.dumps(data, indent=0, ensure_ascii=False)

def to_unicode_hex_escape(char):
    if hasattr(char, 'group'):
        char = char.group(0)
    return f'\\u{ord(char):04x}'

data = re.sub(r'[\x00-\t\v-\x1F]', to_unicode_hex_escape, data)

print(data)
