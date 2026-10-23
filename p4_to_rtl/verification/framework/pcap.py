"""libpcap read/write, and the text form a SystemVerilog testbench can read.

pcap is the framework's USER-FACING format on purpose: a designer verifying
their own P4 program already has their traffic in a pcap (tcpdump, Wireshark,
scapy, a capture off the real network), and that file is the one artifact that
carries the network behaviour they actually care about. Nothing in this
framework asks them to re-describe it in a project-specific format.

The testbench does NOT parse pcap itself. Reading a binary little-endian file
byte-wise through $fread is portable in principle and fragile in practice
across simulators, and this project has paid for that kind of difference
before -- so the conversion happens here, in Python, and the testbench reads a
trivial hex text file instead. pcap stays the interchange format; the text form
is an implementation detail between this module and the generated testbench.

No third-party dependency (no scapy, no dpkt): the format is 24 bytes of
global header plus 16 bytes per packet, and a framework that needs a pip
install to run a regression is one that stops being run.
"""
import struct

PCAP_MAGIC_LE = 0xA1B2C3D4      # microsecond timestamps, little-endian
PCAP_MAGIC_LE_NS = 0xA1B23C4D   # nanosecond timestamps, same layout
LINKTYPE_ETHERNET = 1


class PcapError(Exception):
    pass


def read_pcap(path):
    """Return [(seconds, usec_or_nsec, bytes)] for every packet in `path`."""
    with open(path, 'rb') as f:
        blob = f.read()
    if len(blob) < 24:
        raise PcapError(f'{path}: too short to be a pcap ({len(blob)} bytes)')
    magic = struct.unpack('<I', blob[0:4])[0]
    if magic in (PCAP_MAGIC_LE, PCAP_MAGIC_LE_NS):
        end = '<'
    elif struct.unpack('>I', blob[0:4])[0] in (PCAP_MAGIC_LE, PCAP_MAGIC_LE_NS):
        end = '>'
    else:
        raise PcapError(
            f'{path}: not a pcap file (magic {magic:#010x}). pcapng (the default '
            f'for newer Wireshark saves) is NOT supported -- save as '
            f'"Wireshark/tcpdump/... - pcap" or convert with '
            f'`editcap -F pcap in.pcapng out.pcap`.')
    _vmaj, _vmin, _tz, _sig, snaplen, linktype = struct.unpack(end + 'HHiIII', blob[4:24])
    if linktype != LINKTYPE_ETHERNET:
        raise PcapError(
            f'{path}: link type {linktype}, expected {LINKTYPE_ETHERNET} '
            f'(Ethernet). The generated designs take Ethernet frames on '
            f'AXI4-Stream; a capture with another link layer would need its '
            f'own framing removed first.')
    out, off = [], 24
    while off < len(blob):
        if off + 16 > len(blob):
            raise PcapError(f'{path}: truncated packet header at byte {off}')
        ts_sec, ts_frac, caplen, origlen = struct.unpack(end + 'IIII', blob[off:off+16])
        off += 16
        if off + caplen > len(blob):
            raise PcapError(f'{path}: truncated packet data at byte {off}')
        data = blob[off:off+caplen]
        off += caplen
        # A truncated capture would make the model and the RTL agree on the
        # wrong thing, so it is an error rather than a warning.
        if origlen != caplen:
            raise PcapError(
                f'{path}: packet captured short ({caplen} of {origlen} bytes, '
                f'snaplen {snaplen}) -- recapture with `tcpdump -s 0`.')
        out.append((ts_sec, ts_frac, data))
    return out


def write_pcap(path, packets, linktype=LINKTYPE_ETHERNET):
    """Write [(sec, usec, bytes)] -- or plain [bytes] -- as a pcap."""
    with open(path, 'wb') as f:
        f.write(struct.pack('<IHHiIII', PCAP_MAGIC_LE, 2, 4, 0, 0, 65535, linktype))
        for i, p in enumerate(packets):
            if isinstance(p, (bytes, bytearray)):
                sec, usec, data = i, 0, bytes(p)
            else:
                sec, usec, data = p[0], p[1], bytes(p[2])
            f.write(struct.pack('<IIII', sec, usec, len(data), len(data)))
            f.write(data)


def write_vector(path, packets):
    """Write the text form the generated testbench reads.

    One packet per line: the byte count, then that many hex byte pairs. A
    line-oriented text file is the one thing every simulator in this project
    reads identically.
    """
    # No comment or header line: the testbench reads this with $fscanf("%d"),
    # which cannot skip a comment. The format is documented here instead --
    # one packet per line, the byte count then that many hex byte pairs.
    with open(path, 'w') as f:
        for p in packets:
            data = p if isinstance(p, (bytes, bytearray)) else p[2]
            f.write(f'{len(data)} ' + ' '.join(f'{b:02x}' for b in data) + '\n')


def read_vector(path):
    """Read back what the generated testbench wrote for its output packets."""
    out = []
    with open(path) as f:
        for line in f:
            line = line.split('#')[0].strip()
            if not line:
                continue
            parts = line.split()
            n = int(parts[0])
            data = bytes(int(x, 16) for x in parts[1:1+n])
            if len(data) != n:
                raise PcapError(f'{path}: line claims {n} bytes, carries {len(data)}')
            out.append(data)
    return out
