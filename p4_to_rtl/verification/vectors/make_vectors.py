#!/usr/bin/env python3
"""Regenerate verification/vectors/<app>/traffic.pcap from the spec below.

The pcaps are committed, because a pcap IS the test: it is what a designer
hands this framework for their own program, and ours should be the same kind of
artifact (openable in Wireshark, replayable, diffable against what came out).
They are also GENERATED from the readable spec in this file, so a reviewer can
see what traffic each one contains without opening a binary -- a committed
binary nobody can read is a test nobody can check.

Each app also gets entries.txt: table entries in the same `table_add` form
Vitis Networking P4's behavioural model takes.

    python3 verification/vectors/make_vectors.py          # rewrite them all
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, '..', 'framework'))
import pcap  # noqa: E402

DST = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]
SRC = [0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb]


def eth(etype, payload, dst=None, src=None):
    return bytes(dst or DST) + bytes(src or SRC) + bytes([etype >> 8, etype & 0xff]) + bytes(payload)


def ipv4(src_ip, dst_ip, proto=6, ttl=64, payload=b'', ihl=5, opts=b''):
    """An IPv4 header. `ihl`/`opts` go together: ihl counts 32-bit words of
    HEADER, so 4 bytes of options means ihl=6, and total_length counts the
    options too."""
    assert len(opts) == (ihl - 5) * 4, f'ihl={ihl} wants {(ihl-5)*4} option bytes'
    total = ihl * 4 + len(payload)
    hdr = bytearray([0x40 | ihl, 0x00, total >> 8, total & 0xff,
                     0x12, 0x34, 0x00, 0x00, ttl, proto, 0x00, 0x00])
    hdr += bytes(src_ip) + bytes(dst_ip) + bytes(opts)
    return bytes(hdr) + payload


# NOP,NOP,NOP,End-of-options: 4 bytes, the smallest legal IPv4 option block.
IPV4_OPTS = bytes([0x01, 0x01, 0x01, 0x00])
# TCP's own NOP,NOP,NOP,EOL.
TCP_OPTS = bytes([0x01, 0x01, 0x01, 0x00])


def tcp(sport, dport, seq=0x11223344, ack=0x55667788, flags=0x10,
        window=0x1000, doff=5, opts=b''):
    """A full 20-byte TCP header (plus `opts`), with the fields that are not
    ports carrying NON-ZERO values.

    They used to be twelve zero bytes, and that quietly cost real coverage:
    seqNo, ackNo, dataOffset, flags and window never changed value, so the
    toggle points on those signals only ever fired because a BUG was moving
    the TCP base offset around the buffer on non-IPv4 frames. With the offset
    correct, zero stimulus means zero coverage -- so the stimulus carries
    values instead."""
    assert len(opts) == (doff - 5) * 4, f'doff={doff} wants {(doff-5)*4} option bytes'
    return bytes([sport >> 8, sport & 0xff, dport >> 8, dport & 0xff,
                  (seq >> 24) & 0xff, (seq >> 16) & 0xff, (seq >> 8) & 0xff, seq & 0xff,
                  (ack >> 24) & 0xff, (ack >> 16) & 0xff, (ack >> 8) & 0xff, ack & 0xff,
                  (doff << 4), flags,
                  window >> 8, window & 0xff,
                  0x00, 0x00,            # checksum (the programs here recompute or ignore)
                  0x00, 0x00]) + bytes(opts)   # urgent pointer


def udp(sport, dport, payload=b''):
    ln = 8 + len(payload)
    return bytes([sport >> 8, sport & 0xff, dport >> 8, dport & 0xff,
                  ln >> 8, ln & 0xff, 0x00, 0x00]) + bytes(payload)


def pad_to(frame, n):
    return frame + bytes((0x80 + i) & 0xff for i in range(max(0, n - len(frame))))


# ---------------------------------------------------------------- the spec
# (packets, entries, note) per app. Every packet is chosen to exercise a
# different arm of the program, and the note says what the traffic is FOR --
# that sentence is the thing a reviewer actually needs.
SPEC = {}

SPEC['egprobe'] = (
    [pad_to(eth(0x0001, b''), 64),      # forwarded to port 1, egress rewrites src MAC
     pad_to(eth(0x00F0, b''), 64),      # retagged by ingress, keyed on the NEW etype in egress
     pad_to(eth(0x00AA, b''), 64),      # dropped by ingress
     pad_to(eth(0xBEEF, b''), 64),      # dropped by EGRESS, after ingress forwarded it
     pad_to(eth(0x1234, b''), 64)],     # matches nothing: untouched
    """table_add l2 fwd 0x0001 => 1
table_add l2 retag 0x00F0
table_add l2 drop_pkt 0x00AA
table_add l2 fwd 0xBEEF => 1
table_add port_smac set_smac 1 => 0xAABBCCDDEEFF
table_add port_smac set_smac 2 => 0x112233445566
""",
    'one frame per arm of l2 plus the egress-side drop')

SPEC['lenprobe'] = (
    [pad_to(eth(0x0004, b''), 64),      # unchanged
     pad_to(eth(0x0001, b''), 64),      # +4 bytes inserted
     pad_to(eth(0x0002, b''), 64),      # +8
     pad_to(eth(0x0003, bytes([0x0A, 0xBC, 0x08, 0x00])), 64),   # parsed VLAN removed: -4
     pad_to(eth(0x0005, b''), 96),      # +4, stamped with the RECEIVED length
     pad_to(eth(0x0001, b''), 32)],     # short frame: fits inside the header region
    """table_add cls fwd 0x0004 => 1
table_add cls insert_one 0x0001 => 1
table_add cls insert_two 0x0002 => 1
table_add cls strip_vlan 0x0003 => 1
table_add cls insert_stamp 0x0005 => 1
""",
    'every length change the program can make, including a frame short enough '
    'to live entirely inside the header region')

SPEC['feprobe'] = (
    [pad_to(eth(0x0801, b''), 64),
     pad_to(eth(0x0802, b''), 64),      # dropped: the gated feed must stay silent
     pad_to(eth(0x0801, b''), 128),     # a different length, so packet_length moves
     pad_to(eth(0x9999, b''), 64)],
    """table_add fwd set_port 0x0801 => 5
table_add fwd drop_it 0x0802
""",
    'a forwarded frame, a dropped one, and a longer one so the exported '
    'packet_length field changes')

SPEC['egfeprobe'] = (
    [pad_to(eth(0x0801, b''), 64) for _ in range(4)] + [pad_to(eth(0x0802, b''), 64)],
    """table_add fwd set_port 0x0801 => 5
table_add fwd drop_it 0x0802
""",
    'a burst into one queue, then a dropped frame')

SPEC['qdprobe'] = (
    [pad_to(eth(0x0801, b''), 64) for _ in range(4)]
    + [pad_to(eth(0x0802, b''), 64) for _ in range(2)],
    """table_add fwd set_port 0x0801 => 5
table_add fwd set_port 0x0802 => 6
""",
    'two queues, so the traffic manager has a choice to make')

SPEC['ioprobe'] = (
    [pad_to(eth(0x0800, ipv4([10, 0, 0, 1], [10, 0, 0, 2], payload=tcp(80, 8080))), 64),
     pad_to(eth(0x0800, ipv4([10, 0, 0, 1], [10, 0, 0, 9], payload=tcp(81, 8080))), 120),
     pad_to(eth(0x1234, b''), 64)],
    """table_add port_fwd fwd 3 => 7
""",
    'IPv4 and non-IPv4 frames arriving on the port the entry matches')

SPEC['lmprobe'] = (
    [pad_to(eth(0x0800, ipv4([10, 0, 0, 1], [10, 0, 0, 2], payload=tcp(80, 8080))), 64),
     pad_to(eth(0x0800, ipv4([10, 0, 0, 3], [10, 0, 0, 4], payload=tcp(80, 8080))), 64),
     pad_to(eth(0x1234, b''), 64)],
    """table_add port_fwd fwd 3 => 1
""",
    'frames that accumulate into the egress register')

SPEC['rawprobe'] = (
    [pad_to(eth(0x0801, b''), 64) for _ in range(6)],
    """table_add fwd set_port 0x0801 => 1
""",
    'back-to-back frames, which is what the register read-after-write '
    'distance is about')

# 13 bytes: one short of the Ethernet header these two programs parse, so
# PacketTooShort applies at the very first extract. Both have NO match table,
# which makes their match-action pipeline zero-latency -- issue and completion
# land in the same cycle -- and that is exactly the case where the too-short
# flag used to be read from a register one delta before it was written. The
# check was therefore dead for echo, regprobe and smprobe from the day it was
# added until 2026-10-30, and no pcap had a frame short enough to notice.
def too_short_eth():
    return (bytes(DST) + bytes(SRC) + bytes([0x08]))   # 13 bytes


SPEC['regprobe'] = (
    [pad_to(eth(0x0801, b'', dst=[0, 0, 0, 0, 0, n]), 64) for n in (1, 2, 1, 3)]
    + [too_short_eth()],
    '',
    'repeated destinations, so a register indexed by them is hit more than '
    'once, plus a frame too short to hold an Ethernet header at all')

SPEC['smprobe'] = (
    [pad_to(eth(0x0800, b''), 64),
     pad_to(eth(0xFFFF, b''), 64),      # the verify() in the parser rejects this one
     pad_to(eth(0x0800, b''), 224),
     too_short_eth()],
    '',
    'a good frame, one the parser verify() rejects, a long one, and one too '
    'short to hold an Ethernet header')

# A frame that ENDS before its parse path completes: IPv4 says proto=6 so the
# parser wants a TCP header, and there isn't one. P4 calls that PacketTooShort
# and the parser rejects; the design discards it. This frame is here because
# that check was ADDED on 2026-10-28 after the randomised stimulus found the
# design forwarding such packets, having read TCP fields out of bytes that were
# never received -- so the committed stimulus should keep exercising it.
def truncated_tcp():
    return (bytes(DST) + bytes(SRC) + bytes([0x08, 0x00])
            + ipv4([10, 0, 1, 1], [10, 0, 2, 1], proto=6))   # no TCP header


SPEC['load_balance_p4rtl'] = (
    [pad_to(eth(0x0800, ipv4([10, 0, 1, 1], [10, 0, 2, n], payload=tcp(1000 + n, 80))), 78)
     for n in (1, 2, 3)]
    + [pad_to(eth(0x0800, ipv4([10, 0, 1, 1], [192, 168, 0, 1], payload=tcp(5000, 80))), 78),
       pad_to(eth(0x1234, b''), 64),
       truncated_tcp(),
       # IPv4 WITH OPTIONS. This program's parser is `extract(ipv4);
       # extract(tcp)`, so P4 places tcp 20 bytes after ipv4 whatever ihl
       # says -- the options are read as the TCP header, and the program is
       # simply wrong about packets like this one. That is the PROGRAM's bug,
       # not the compiler's, and the compiler now warns about it.
       #
       # The frame is here because the compiler used to "help" by skipping
       # the options, placing tcp at ipv4+ihl*4. Measured against the
       # reference model this frame went to the wrong next hop, and no
       # committed pcap carried an IPv4 option, so the oracle never saw it.
       pad_to(eth(0x0800, ipv4([10, 0, 1, 1], [10, 0, 2, 1], ihl=6, opts=IPV4_OPTS,
                               payload=tcp(1001, 80))), 82)],
    """# ecmp_group is an LPM table: 10.0.2.0/24 spreads over two next hops
table_add ecmp_group set_ecmp_select 0x0A000200/24 => 0 1
table_add ecmp_nhop set_nhop 0 => 0x00000A000001 0x0A000101 1
table_add ecmp_nhop set_nhop 1 => 0x00000A000002 0x0A000102 2
table_add send_frame rewrite_mac 1 => 0x00AABB000001
table_add send_frame rewrite_mac 2 => 0x00AABB000002
""",
    'three flows that hash across two next hops, one address outside the '
    'prefix, a non-IPv4 frame, one frame that ends before its TCP header '
    '(PacketTooShort) and one carrying IPv4 options (which this program does '
    'not extract, so P4 reads them as its TCP header); the IPv4 checksum is '
    'recomputed for each')

SPEC['ecn_p4rtl'] = (
    [pad_to(eth(0x0800, ipv4([10, 0, 0, 1], [10, 0, 0, 1], proto=17,
                             payload=bytes([0x1f, 0x90, 0, 80, 0, 8, 0, 0]))), 64)
     for _ in range(4)],
    """table_add ipv4_lpm ipv4_forward 0x0A000001/8 => 0x0000BB000001 1
""",
    'a burst at one destination, which is what builds the queue depth ECN '
    'reacts to')


# The XSA build of the same program: identical tables, except send_frame keys
# on meta.egress_port (xsa.p4 has no standard egress_port), so the same traffic
# and the same entries apply.
SPEC['load_balance_xsa'] = (SPEC['load_balance_p4rtl'][0],
                            SPEC['load_balance_p4rtl'][1],
                            SPEC['load_balance_p4rtl'][2] + ' (XSA architecture)')

# ── The two programs with variable-length (varbit) headers ──────────────────
# These are the reason the framework can model varbit at all. Both extract an
# IPv4 options header with a runtime length, so unlike load_balance above they
# are CORRECT about a packet carrying options -- and the traffic below is what
# proves it, by sending the same flow with 0, 4 and 8 bytes of options and
# requiring the same table to match each time.
FT_SRC, FT_DST = [10, 0, 1, 1], [10, 0, 2, 5]

SPEC['fiveTuple'] = (
    [# the matching flow with no options at all
     pad_to(eth(0x0800, ipv4(FT_SRC, FT_DST, payload=tcp(1111, 80))), 78),
     # ...with 4 bytes of IPv4 options: ihl=6, and because the program
     # extracts hdr.ipv4opt as a varbit, tcp still starts after them, so the
     # SAME entry has to match. It did not before 2026-10-30: ipv4opt was
     # placed at the END of its own options and tcp 4 bytes too far along.
     pad_to(eth(0x0800, ipv4(FT_SRC, FT_DST, ihl=6, opts=IPV4_OPTS,
                             payload=tcp(1111, 80))), 82),
     # ...and with 8
     pad_to(eth(0x0800, ipv4(FT_SRC, FT_DST, ihl=7, opts=IPV4_OPTS * 2,
                             payload=tcp(1111, 80))), 86),
     # 4 bytes of TCP options: the SECOND varbit header on the path, whose
     # base offset depends on the FIRST one's runtime length. This is the
     # case the old single-length-field model could not express at all --
     # tcpopt was placed on top of tcp.
     pad_to(eth(0x0800, ipv4(FT_SRC, FT_DST,
                             payload=tcp(1111, 80, doff=6, opts=TCP_OPTS))), 82),
     # both variable regions at once
     pad_to(eth(0x0800, ipv4(FT_SRC, FT_DST, ihl=6, opts=IPV4_OPTS,
                             payload=tcp(1111, 80, doff=6, opts=TCP_OPTS))), 86),
     # the UDP arm of the apply block, matching its own entry
     pad_to(eth(0x0800, ipv4(FT_SRC, FT_DST, proto=17,
                             payload=udp(53, 53, bytes(4)))), 64),
     # a TCP flow that matches nothing: no VLAN inserted
     pad_to(eth(0x0800, ipv4(FT_SRC, [10, 9, 9, 9], payload=tcp(1111, 80))), 78),
     # not IPv4 at all
     pad_to(eth(0x1234, b''), 64),
     # ends inside the TCP header: PacketTooShort, which this program could
     # not be given until its cutoff became exact
     eth(0x0800, ipv4(FT_SRC, FT_DST, payload=tcp(1111, 80)))[:-6],
     # The EXACTNESS boundary, and the reason the check can be switched on for
     # a varbit program at all. With 4 bytes of IPv4 options the parse path
     # needs exactly 14 + 20 + 4 + 20 = 58 bytes. This frame is 58 and must be
     # FORWARDED; the next is 57 and must be DROPPED. A bound using the
     # varbit's declared maximum instead of its runtime length would demand
     # 14 + 20 + 40 + 20 + 40 and reject both.
     eth(0x0800, ipv4(FT_SRC, FT_DST, ihl=6, opts=IPV4_OPTS,
                      payload=tcp(1111, 80))),
     eth(0x0800, ipv4(FT_SRC, FT_DST, ihl=6, opts=IPV4_OPTS,
                      payload=tcp(1111, 80)))[:-1],
     # dataOffset = 0 makes (dataOffset - 5) * 32 wrap to four billion bits:
     # P4's HeaderTooShort, which the shell now rejects. The randomised
     # stimulus found the design forwarding one of these, having placed TCP
     # options 40 bytes past a header that has none.
     pad_to(eth(0x0800, ipv4(FT_SRC, FT_DST,
                             payload=bytes([0x04, 0x57, 0x00, 0x50]) + bytes(16))), 78)],
    """table_add FiveTuple InsertVLAN 0x0A000101 0x0A000205 0x06 0x0457 0x0050 => 0 1 0 100
table_add FiveTuple InsertVLAN 0x0A000101 0x0A000205 0x11 0x0035 0x0035 => 1 2 0 200
""",
    'the same 5-tuple with 0, 4 and 8 bytes of IPv4 options and with TCP '
    'options, so the varbit lengths have to be right for the table to match; '
    'the 58/57-byte boundary of the exact PacketTooShort bound; a frame whose '
    'tcp.dataOffset asks for more option bytes than the varbit holds '
    '(HeaderTooShort); plus the UDP arm, a miss, a non-IPv4 frame and a '
    'truncated one')

SPEC['echo'] = (
    [# UDP to port 0 (meta.echo_port is never assigned, so it is 0): echoed,
     # with MACs, addresses and ports swapped
     pad_to(eth(0x0800, ipv4([10, 0, 1, 1], [10, 0, 2, 5], proto=17,
                             payload=udp(4000, 0, bytes(4)))), 64),
     # the same, carrying 4 bytes of IPv4 options: the swap must still happen
     # and the options must come back out unchanged
     pad_to(eth(0x0800, ipv4([10, 0, 1, 1], [10, 0, 2, 5], proto=17,
                             ihl=6, opts=IPV4_OPTS,
                             payload=udp(4000, 0, bytes(4)))), 68),
     # UDP to a port it is not listening on: untouched
     pad_to(eth(0x0800, ipv4([10, 0, 1, 1], [10, 0, 2, 5], proto=17,
                             payload=udp(4000, 53, bytes(4)))), 64),
     # not IPv4
     pad_to(eth(0x1234, b''), 64),
     # IPv4 says UDP, and the frame ends at the end of the IPv4 header: the
     # parse path needs 42 bytes and has 34. The randomised stimulus found
     # the design forwarding this one -- see too_short_eth() above.
     eth(0x0800, ipv4([10, 0, 1, 1], [10, 0, 2, 5], proto=17))],
    '',
    'a datagram on the echo port with and without IPv4 options, one on '
    'another port, a non-IPv4 frame, and one that ends before its UDP header')


# Extra compiler flags per app, where the committed build uses them: the
# framework must verify the design as it is actually built, not a default one.
# Only flags that change the DESIGN belong here. fiveTuple's and echo's
# committed builds pass --self-test and --board, which add a wrapper and a RAM
# pragma beside <app>_top.sv without altering it, so the framework drives the
# same core either way.
FLAGS = {'qdprobe': '--nslot 8'}


def main():
    for app, (packets, entries, note) in sorted(SPEC.items()):
        d = os.path.join(_HERE, app)
        os.makedirs(d, exist_ok=True)
        pcap.write_pcap(os.path.join(d, 'traffic.pcap'), packets)
        with open(os.path.join(d, 'entries.txt'), 'w') as f:
            f.write(f'# {app}: {note}\n')
            f.write('# Regenerate with verification/vectors/make_vectors.py\n')
            if entries:
                f.write(entries)
            else:
                f.write('# (this program has no tables to program)\n')
            f.write('run_traffic traffic\n')
        if app in FLAGS:
            with open(os.path.join(d, 'flags.txt'), 'w') as f:
                f.write(FLAGS[app] + '\n')
        print(f'{app:22s} {len(packets)} packet(s), '
              f'{sum(1 for l in entries.splitlines() if l.startswith("table_add"))} entry/entries'
              f'  -- {note}')


if __name__ == '__main__':
    main()
