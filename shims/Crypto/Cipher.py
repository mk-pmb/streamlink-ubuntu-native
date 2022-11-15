# -*- coding: UTF-8, tab-width: 4 -*-

try:
    from Cryptodome.Cipher import (
        AES,
        Blowfish,
        PKCS1_v1_5,
        )
except ModuleNotFoundError:
    AES = 'stub'
    Blowfish = 'stub'
    PKCS1_v1_5 = 'stub'
