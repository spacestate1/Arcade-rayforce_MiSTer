#!/usr/bin/env python3
"""Taito F3 graphics decoding, ported from the gfx_layouts in taito_f3.cpp.

Every layout here was taken from the MAME source, not guessed:

  playfield/sprite low 4bpp  gfx_16x16x4_packed_lsb  (src/emu/video/generic.cpp)
      xoffset { 1*4, 0*4, 3*4, 2*4, ... }  -- low nibble is the FIRST pixel,
      so a row of 16 pixels is 8 bytes, pixel 2k = byte&0x0f, 2k+1 = byte>>4.

  playfield hi 2bpp          layout_6bpp_tile_hi
      planes { 8, 0 } -> bit5 at +8, bit4 at +0; xoffset { STEP8(7,-1),
      STEP8(23,-1) }; 4 bytes per row. Per row: byte0 = bit4 for pixels 0-7
      (LSB = pixel 0), byte1 = bit5 for 0-7, byte2/3 the same for 8-15.

  sprite hi 2bpp             layout_6bpp_sprite_hi
      planes { 0, 1 } -> bit5 at +0, bit4 at +1; xoffset steps of -2, so each
      byte packs four pixels as (bit4,bit5) pairs, LSB first.

  char / pivot 4bpp 8x8      charlayout / pivotlayout
      xoffset { 20,16,28,24,4,0,12,8 } -- nibbles in the order
      byte2lo, byte2hi, byte3lo, byte3hi, byte0lo, byte0hi, byte1lo, byte1hi.

MAME numbers bits MSB-first inside a byte (readbit uses 0x80 >> (n%8)), and
planeoffset[0] is the MOST significant plane. Both conventions are baked into
the unpacking below.

The 6bpp merge is what taito_f3.cpp tile_decode() does at load time:
    pixel = (low & 0x0f) | (hi & 0x30)
On real hardware there is no merge pass -- the two ROM planes are simply read
in parallel -- so the RTL fetches from both regions and concatenates. Same
result, and this file is where that equivalence is written down.
"""

import numpy as np


def decode_4bpp_packed_lsb(data, tiles=None):
    """gfx_16x16x4_packed_lsb -> (n, 16, 16) uint8, values 0-15."""
    b = np.frombuffer(data, np.uint8)
    n = len(b) // 128
    if tiles is not None:
        n = min(n, tiles)
    b = b[:n * 128].reshape(n, 16, 8)
    out = np.empty((n, 16, 16), np.uint8)
    out[:, :, 0::2] = b & 0x0F        # low nibble is the first pixel
    out[:, :, 1::2] = b >> 4
    return out


def decode_tile_hi(data):
    """layout_6bpp_tile_hi -> (n, 16, 16) uint8 holding bits 4-5 only."""
    b = np.frombuffer(data, np.uint8)
    n = len(b) // 64
    b = b[:n * 64].reshape(n, 16, 4)
    # bitorder='little' gives bit 0 of each byte first, which is pixel 0
    bits = np.unpackbits(b, axis=2, bitorder='little')        # (n,16,32)
    out = np.empty((n, 16, 16), np.uint8)
    out[:, :, 0:8]  = (bits[:, :, 0:8]   << 4) | (bits[:, :, 8:16]  << 5)
    out[:, :, 8:16] = (bits[:, :, 16:24] << 4) | (bits[:, :, 24:32] << 5)
    return out


def decode_sprite_hi(data):
    """layout_6bpp_sprite_hi -> (n, 16, 16) uint8 holding bits 4-5 only."""
    b = np.frombuffer(data, np.uint8)
    n = len(b) // 64
    b = b[:n * 64].reshape(n, 16, 4)
    bits = np.unpackbits(b, axis=2, bitorder='little')        # (n,16,32)
    # each byte is four pixels as (bit4, bit5) pairs, LSB first
    return ((bits[:, :, 0::2] << 4) | (bits[:, :, 1::2] << 5)).astype(np.uint8)


def decode_char(data):
    """charlayout / pivotlayout -> (n, 8, 8) uint8, values 0-15.

    THE BYTE-ORDER TRAP. char RAM and pivot RAM are big-endian u16 shares, but
    video_start() hands them to the gfx decoder as raw bytes:

        m_gfxdecode->gfx(0)->set_source(reinterpret_cast<u8 *>(m_charram.target()));

    On a little-endian host that cast swaps the two bytes of every word
    relative to the 68020's view of the same memory -- and MAME's picture is
    right, so that swapped order is what the real chip reads. charlayout's
    xoffset { 20,16,28,24,4,0,12,8 } is written against the swapped bytes.
    Expressed against the memory image the CPU wrote (which is what an FPGA
    reads out of BRAM), the order is simply descending: pixel 0 is the low
    nibble of byte 3, pixel 7 the high nibble of byte 0.

    Getting this wrong scrambles pixel pairs inside every character while
    leaving the text in the right place on screen, which reads as a font
    problem rather than a byte-order problem. Cost to find: one afternoon.
    """
    b = np.frombuffer(data, np.uint8)
    n = len(b) // 32
    b = b[:n * 32].reshape(n, 8, 4)
    out = np.empty((n, 8, 8), np.uint8)
    out[:, :, 0] = b[:, :, 3] & 0x0F
    out[:, :, 1] = b[:, :, 3] >> 4
    out[:, :, 2] = b[:, :, 2] & 0x0F
    out[:, :, 3] = b[:, :, 2] >> 4
    out[:, :, 4] = b[:, :, 1] & 0x0F
    out[:, :, 5] = b[:, :, 1] >> 4
    out[:, :, 6] = b[:, :, 0] & 0x0F
    out[:, :, 7] = b[:, :, 0] >> 4
    return out


def load_playfield_gfx(lo_path, hi_path):
    lo = decode_4bpp_packed_lsb(open(lo_path, 'rb').read())
    hi = decode_tile_hi(open(hi_path, 'rb').read())
    n = min(len(lo), len(hi))
    return (lo[:n] | hi[:n])


def load_sprite_gfx(lo_path, hi_path):
    lo = decode_4bpp_packed_lsb(open(lo_path, 'rb').read())
    hi = decode_sprite_hi(open(hi_path, 'rb').read())
    n = min(len(lo), len(hi))
    return (lo[:n] | hi[:n])
