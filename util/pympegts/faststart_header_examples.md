
How to detect faststart?
========================

You'd think `ffprobe` can do it, but I couldn't find a straight-forward way.
In order to not fail, `ffprobe` needs to read the entire `moov` atom.
I think reading the first KiB should be enough.
Of course we could feed it only the first KiB and then branch on whether the
error message is "moov atom not found" or "error reading header", but that's
quite dirty. If we allow that level of dirtiness, we don't need to require
`ffprobe` being installed and waste resources for a subprocess, we can just
do a little dirty work ourselves and parse the relevant bytes.


Example of a video with faststart
---------------------------------

```bash
head --bytes=64 -- faststart.mp4 | xxd -c 4 -g 1 | cut --bytes=5-
```

```text
0000: 00 00 00 20  ...  # This box is 0x20 = 32 bytes long.
0004: 66 74 79 70  ftyp # Box type is ftyp
0008: 69 73 6f 6d  isom # Major brand is ISO media
000c: 00 00 02 00  .... # ISO standard minor version = 512
# Odd. I expected v2, but ffprobe says "minor_version   : 512"
# Now for the compatibility declarations:
# The container in this file is compatible with…
0010: 69 73 6f 6d  isom # ISO media
0014: 69 73 6f 32  iso2 # ISO base media file format v2
0018: 61 76 63 31  avc1 # H.264/AVC video
001c: 6d 70 34 31  mp41 # MPEG-4 video
# End of ftyp
0020: 00 51 f4 e6  .Q.. # A large box?
# $(( 0x0051f4e6 / 0x0100000 )) = 5 ⇒ 5 MiB ≤ length < 6 MiB
# confirm? `units -t $(( 0x0051f4e6 ))' bytes' MiB` = 5.1222897
0024: 6d 6f 6f 76  moov # It's a movie box (moov atom)
# So we have 5+ MiB of movie meta data ahead.
# Explains why in this example, VLC needs at least 6 MB to start playing it.
0028: 00 00 00 6c  ...l # First box inside the moov is 108 bytes
002c: 6d 76 68 64  mvhd # It's a movie header box
0030: 00 00 00 00  .... # 1 byte version, 3 bytes flags
0034: 00 00 00 00  .... # Creation time as Macintosh timestamp, 1st half
0038: 00 00 00 00  .... # 2nd half of timestamp.
003c: 00 00 03 e8  .... # Time scale = 1000 = milliseconds
```


Example of a video without faststart
------------------------------------

```bash
head --bytes=64 -- lamestart.mp4 | xxd -c 4 -g 1 | cut --bytes=5-
```

```text
# ftyp box is exactly the same as above, then:


```text
0000: 00 00 00 20  ...  # This box is 0x20 = 32 bytes long.
0004: 66 74 79 70  ftyp # Box type is ftyp
0008: 69 73 6f 6d  isom # Major brand is ISO media
000c: 00 00 02 00  .... # ISO standard minor version = 512
# Odd. I expected v2, but ffprobe says "minor_version   : 512"
# Now for the compatibility declarations:
# The container in this file is compatible with…
0010: 69 73 6f 6d  isom # ISO media
0014: 69 73 6f 32  iso2 # ISO base media file format v2
0018: 61 76 63 31  avc1 # H.264/AVC video
001c: 6d 70 34 31  mp41 # MPEG-4 video
# End of ftyp
0020: 00 00 00 08  .... # Box is 8 bytes long
0024: 66 72 65 65  free # Box type is "free" = "please ignore".
# Why would ffmpeg put these 8 useless bytes then?
0028: 0f df 80 c9  .... # Large box: $(( 0x0fdf80c9 / 0x0100000 )) ≈ 253 MiB
002c: 6d 64 61 74  mdat # Box type is mdat = media data = actual video frames
0030: 00 00 00 02  .... # (video data)
0034: 09 f0 00 00  .... # (video data)
0038: 00 1b 67 4d  ..gM # (video data)
003c: 40 1e ec a0  @... # (video data)
```



