#!/usr/bin/python3
# -*- coding: UTF-8, tab-width: 4 -*-


def mpegts_make_header(pid, tei=False, prio=False, chunk_num=0,
    has_adaptation_field=False, has_payload=False) -> bytes:
    """
    Constrict MPEG-TS header bytes.

    Args:
        pid (int): Packet IDentifier
        tei (bool): Transport Error Indicator
        chunk_num (long): How many packets have already been sent for this
            payload. Used to decide PUSI and continuity counter.

    Returns:
        bytes: MPEG-TS packet header. Always 4 bytes.
    """
    sync_byte = b'G' # aka 0x47

    pusi = (chunk_num == 0)
    tei_pusi_pid = (
        (int(tei) << 15)
        + (int(pusi) << 14)
        + (int(prio) << 13)
        + pid
        ).to_bytes(2, 'big')

    tsc = 0 # No scrambled. We don't support scrambling.
    flags_cc_byte = (
        (tsc << 6)
        + (has_adaptation_field << 5)
        + (has_payload << 4)
        + (chunk_num % 16) # same as & 0x0F
        ).to_bytes(1, 'big')

    return sync_byte + tei_pusi_pid + flags_cc_byte






# scroll
