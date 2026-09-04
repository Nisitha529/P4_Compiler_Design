"""
crc_model.py — reference CRC implementations plus the GF(2) decomposition used
to emit them as flat combinational XOR networks.

A CRC with a fixed message length is an *affine* function over GF(2):
    crc(m) = L(m) XOR c
where L is linear (so each of its output bits is the XOR of a fixed subset of
the message bits) and c is a constant determined by the algorithm's init/xorout
values and the message length. Both parts are compile-time constants once the
field list is known, so the whole CRC emits as `width` reduction-XORs over
constant masks, plus one constant XOR -- one flat combinational network, no
LFSR loop, no state. This mirrors how the rest of this compiler generates wide
functions (Python-unrolled at emit time, never a runtime SystemVerilog loop).

c is obtained as crc(all-zero message of the same length), since L(0) = 0 and
therefore crc(0) = c.

Byte order: the input is treated as a big-endian bit vector, i.e. Verilog
`d[N-1]` is the first/leftmost bit of the message, matching what a
`{field_a, field_b, ...}` concatenation produces. If N is not a multiple of 8
the vector is zero-padded on the MSB side to the next byte boundary (a
documented choice -- P4 hash/checksum field lists are normally byte-aligned, so
this only affects unusual field lists).
"""

# (reflected polynomial, width, init, xorout) -- reflected/LSB-first form.
_ALGOS = {
    # CRC-16/ARC: the variant bmv2's HashAlgorithm.crc16 uses, so apps ported
    # from the v1model versions hash consistently with their originals.
    'CRC16': (0xA001,     16, 0x0000,     0x0000),
    # CRC-32/ISO-HDLC: the standard zlib/Ethernet CRC-32.
    'CRC32': (0xEDB88320, 32, 0xFFFFFFFF, 0xFFFFFFFF),
}


def supported_algos():
    return sorted(_ALGOS)


def crc(algo, data):
    """Reference CRC over a bytes-like message, with the algorithm's real
    init/xorout applied. Ground truth for both mask derivation and tests."""
    poly, width, init, xorout = _ALGOS[algo]
    mask = (1 << width) - 1
    reg = init & mask
    for byte in data:
        reg ^= byte
        for _ in range(8):
            reg = (reg >> 1) ^ poly if (reg & 1) else (reg >> 1)
    return (reg ^ xorout) & mask


def _padded_bytes(value, n_bits):
    pad = (-n_bits) % 8
    return value.to_bytes((n_bits + pad) // 8, 'big')


def crc_masks(algo, n_bits):
    """Return (masks, width, const): output bit j is
        crc[j] = ^(d & masks[j]) ^ ((const >> j) & 1)
    for the Verilog input vector d[n_bits-1:0].

    masks come from evaluating the *linear* part on each one-hot message
    (differencing against crc(0) to cancel the affine constant); const is
    crc(0) itself."""
    if algo not in _ALGOS:
        raise ValueError(
            f'unsupported hash algorithm {algo!r}; supported: {supported_algos()}')
    _, width = _ALGOS[algo][0], _ALGOS[algo][1]

    const = crc(algo, _padded_bytes(0, n_bits))
    total = n_bits + ((-n_bits) % 8)

    masks = [0] * width
    for i in range(n_bits):          # i = Verilog bit index into d[n_bits-1:0]
        pos = total - 1 - i          # distance from the leftmost message bit
        one_hot = 1 << (total - 1 - pos)
        # XOR out the constant to isolate the linear response L(e_i).
        lin = crc(algo, _padded_bytes(one_hot, n_bits)) ^ const
        for j in range(width):
            if (lin >> j) & 1:
                masks[j] |= (1 << i)
    return masks, width, const


def crc_of_bitvector(algo, value, n_bits):
    """Reference CRC of an n_bits-wide integer treated as the same big-endian,
    MSB-zero-padded bit vector crc_masks() models. For test ground truth."""
    return crc(algo, _padded_bytes(value, n_bits))
