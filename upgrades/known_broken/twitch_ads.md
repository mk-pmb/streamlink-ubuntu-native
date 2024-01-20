
Twitch ad-block effects
=======================

All reported behavior are individual observations. Your mileage may vary.


Using Ubuntu focal's ancient libraries
--------------------------------------

* With adblock option `--twitch-disable-ads`:
  * A high risk of startup failure with
    `AttributeError: '_HTTPResponse' object has no attribute 'drain_conn'`
    ([#4938](https://github.com/streamlink/streamlink/issues/4938))
  * When SL managed to start the stream in VLC,
    playback stalls as soon as an ad break starts,
    sometimes even freezing VLC's user interface.
    Recording pretends to continue but VLC cannot play the file beyond
    the start of the ad break.

* Without the adblock option:
  * Surprisingly, enabling ads did not actually show ads,
    but instead it showed text messages that reminded of a loading screen.
    * For the pre-roll (start of stream) ads,
      the messages were meant-to-be-funny bogus progress reports.
    * In mid-stream, it was just "Commercial break in progress".
  * Unfortunately, the real stream then had bad audio:
    It was high-pitched and with a short gap about every second.
    My speculation for why this happened is that the loading screen uses
    another codec than the steamer and VLC doesn't understand the hand-over.
  * Update 2023-11-01:
    Nowadays most streams I watch work without noticeable pitch shift.
    The stream discontinuities introduced by ad breaks confuse VLC's video
    position slider and its seek mechanism. One way to fix them in a recorded
    file is to convert it in `ffmpeg` with `copy` codec, thus only rewriting
    the container.
    The script `util/twitch_fix_stream_discontinuity.sh` simplifies that.




Using upgraded libraries
------------------------

* With adblock option `--twitch-disable-ads`:
  * Stream starts reliably.
  * `[plugins.twitch][info] Will skip ad segments`
  * Playback stalls as soon as a mid-stream ad break starts.
    However, I did not encounter any VLC UI freeze.
    * Sometimes playback recovers and continues after the mid-stream ad ends.

* Without the adblock option:
  * Pre-roll ad consists of bogus loading screen messages.
  * At least in the recording, after the pre-roll messages are over,
    * audio is broken as described above.
    * time position makes a huge jump ahead to the future.
  * Mid-stream ads show the "Commercial break in progress" message.
  * The time position in the live VLC's status bar works normally until
    a mid-stream ad starts, then switches to `00:00 / 00:00`
    or `##:## / --:--` where `##:##` is the time since ad start.
  * When the recorded file contains a mid-stream ad,
    time position in VLC's status bar shows a negative duration.
  * After a mid-stream ad, playback continues smoothly but the time position
    warps forward a lot.










