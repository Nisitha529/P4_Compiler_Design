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


def ipv4(src_ip, dst_ip, proto=6, ttl=64, payload=b'', ihl=5):
    hdr = bytearray([0x40 | ihl, 0x00, 0x00, 20 + len(payload),
                     0x12, 0x34, 0x00, 0x00, ttl, proto, 0x00, 0x00])
    hdr += bytes(src_ip) + bytes(dst_ip)
    return bytes(hdr) + payload


def tcp(sport, dport, pad=12):
    return bytes([sport >> 8, sport & 0xff, dport >> 8, dport & 0xff]) + bytes(pad)


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

SPEC['regprobe'] = (
    [pad_to(eth(0x0801, b'', dst=[0, 0, 0, 0, 0, n]), 64) for n in (1, 2, 1, 3)],
    '',
    'repeated destinations, so a register indexed by them is hit more than once')

SPEC['smprobe'] = (
    [pad_to(eth(0x0800, b''), 64),
     pad_to(eth(0xFFFF, b''), 64),      # the verify() in the parser rejects this one
     pad_to(eth(0x0800, b''), 224)],
    '',
    'a good frame, one the parser verify() rejects, and a long one')

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
       truncated_tcp()],
    """# ecmp_group is an LPM table: 10.0.2.0/24 spreads over two next hops
table_add ecmp_group set_ecmp_select 0x0A000200/24 => 0 1
table_add ecmp_nhop set_nhop 0 => 0x00000A000001 0x0A000101 1
table_add ecmp_nhop set_nhop 1 => 0x00000A000002 0x0A000102 2
table_add send_frame rewrite_mac 1 => 0x00AABB000001
table_add send_frame rewrite_mac 2 => 0x00AABB000002
""",
    'three flows that hash across two next hops, one address outside the '
    'prefix, a non-IPv4 frame, and one frame that ends before its TCP header '
    '(PacketTooShort); the IPv4 checksum is recomputed for each')

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

# Extra compiler flags per app, where the committed build uses them: the
# framework must verify the design as it is actually built, not a default one.
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
