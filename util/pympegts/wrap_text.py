#!/usr/bin/python3
# -*- coding: UTF-8, tab-width: 4 -*-


from make_header import mpegts_make_header


def mpegts_wrap_text(pid, text, table_id=0) -> list:
    """
    Wrap UTF-8 encoded text in an MPEG-TS private section packet.

    Args:
        pid (int or bytes): Program ID for the packets.
        text (str or bytes): Text to be wrapped. If str, will be encoded as UTF-8.

    Returns:
        list: MPEG-TS packets containing the wrapped text.
    """

    if not isinstance(text, bytes):
        text = str(text).encode('utf-8')

    packet_length = 188
    packet_header_length = 4
    private_section_header_length = 3
    private_section_length = (packet_length
        - packet_header_length
        - private_section_header_length
        )

    private_section_header = (
        (int(table_id) << 16)
        # + (0 << 15) # section_syntax_indicator
        + (1 << 14) # private_indicator
        # + (1 << 13) # reserved_bit_1
        # + (1 << 12) # reserved_bit_2
        + private_section_length
        ).to_bytes(private_section_header_length, 'big')

    crc_length = 0
    # No CRC: According to MPEG-Poster-ATSC-21W150204.pdf [1],
    # a CRC is used only when the section_syntax_indicator is set.
    # [1] www.telestream.net/pdfs/technical/MPEG-Poster-ATSC-21W150204.pdf

    chunk_size = private_section_length - crc_length
    chunk_num = 0
    packets = []

    while text:
        chunk_data = text[0:chunk_size]
        text = text[chunk_size:]
        pad_length = chunk_size - len(chunk_data)
        if pad_length:
            chunk_data += b'\x00' * pad_length
        packets.append(mpegts_make_header(pid=pid, chunk_num=chunk_num)
            + private_section_header + chunk_data)
        chunk_num += 1

    return packets




if __name__ == '__main__':
    from sys import argv, stdin, stdout
    pid, table_id, *ignore = map(int, argv[1:] + [0])
    packets = mpegts_wrap_text(pid=pid, text=stdin.read(), table_id=table_id)
    for packet in packets:
        stdout.buffer.write(packet)









# scroll
