#!/bin/sed -urf
# -*- coding: UTF-8, tab-width: 2 -*-

s~\b(X-TV-TWITCH-(SESSION|SERVING|NODE|CLUSTER)(-?ID|)=")[^"]+"~\1…"~g
s~(#EXT-X-DATERANGE:ID="([a-z]+-)*)[^"]*~\1…~g

s~\b(\
  $1  prefix:   |https://video-(edge-|weaver\.)\b)(\
  $3  node id:  |[a-z0-9-]+|)\.(\
  $4  cluster:  |[a-z0-9-]+)(\
  $5  type:     |\.[a-z0-9.-]+|)(\
  $6  domain:   |\.ttvnw\.net/|\
  )~\1…\6\f~g
s~/\f([A-Za-z0-9_/-]+/)([A-Za-z0-9_-]+)(\.ts|)\b~/\1…\3~g

s~^\[([a-z]+) @ 0x[0-9a-fA-F]+\] ~\1: ~
/^hls: Skip \('#EXT-X-PROGRAM-DATE-TIME:/d
/^frame=[0-9 ]+ fps=[0-9 ]+ /d



