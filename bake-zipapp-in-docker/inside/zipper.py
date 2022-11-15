#!/usr/bin/python3
# -*- coding: UTF-8, tab-width: 4 -*-

import zipfile
from sys import argv

def main(invocation, dest, src):
    with zipfile.PyZipFile(dest, mode='w') as zip_pkg:
        zip_pkg.writepy(src)

main(*argv)
