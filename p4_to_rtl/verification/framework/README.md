# pcap verification framework

Point this at **your own P4 program and your own pcap**. It compiles the
program, runs your traffic through the generated RTL in a simulator, runs the
same traffic through a reference model built from the compiler's own IR, and
compares the two byte for byte.

```bash
python3 verification/framework/p4v.py my_app \
        --pcap capture.pcap \
        --testcase entries.txt
```

```
my_app: PASS -- 7 packet(s) matched
```

Nothing about it is specific to the applications in this repository: the
reference model is driven by the IR, so it covers any program the compiler
accepts, and the testbench is generated per app from the generated top's own
port list.

## What you supply

**The pcap** is the point of the design. The traffic that matters for your
program is the traffic you already have — from `tcpdump`, from Wireshark, from
`scapy`, from a capture off the real network — and that file carries the network
behaviour you care about. Save it as pcap, not pcapng (`editcap -F pcap in.pcapng
out.pcap`), Ethernet link type, full frames (`tcpdump -s 0`).

**The testcase file** holds the table entries, in the same `table_add` shape
Vitis Networking P4's behavioural model uses:

```
# key forms:  <value>  |  <value>/<prefix_len> for lpm  |  <value>&<mask> for ternary
table_add ipv4_lpm  ipv4_forward 0x0A000001/8 => 0x0000BB000001 1
table_add send_frame rewrite_mac 1 => 0x00AABB000001
table_add acl       permit 0x0800&0xFFFF priority=10
run_traffic capture
```

Entries are written **once** and used twice: translated into AXI4-Lite word
writes for the hardware (via the `cp_map`, which already describes every
table's words, action ids and key widths) and into match-action entries for the
model. There is no second place to keep them in step.

## What comes back

| verdict | meaning |
|---|---|
| `PASS` | every packet matched |
| `FAIL` | they differ — the first differing packet and byte are printed, and both sides are written out as `expected.pcap` / `actual.pcap` for you to open in Wireshark |
| `REORDERED` | the same packets, in a different order. Across output queues the traffic manager is allowed to reorder; within one queue it is not |
| `VACUOUS` | nothing came out on either side, so the run proves nothing. Usually means no table entries, or traffic the program does not forward |
| `NOT VERIFIED` | the model cannot represent some construct in your program, and says which |

`NOT VERIFIED` is the important one. The model never approximates: an oracle
that guesses and reports `PASS` is worse than no oracle, so anything outside
what it can model faithfully stops the run and names the construct.

## What it does and does not check

It consumes the **same IR the emitters consume**. So it catches bugs in the
emitters and the shell — which is every datapath bug this project has actually
found — and it cannot catch a program that was mis-*ingested*, because both
sides would then be wrong in the same way. For an oracle independent of the
front end you would need one derived from the P4 spec itself (`p4testgen`'s
symbolic execution is the obvious candidate); that is not what this is.

Two more limits worth stating plainly:

* **Hash and checksum algorithms** come from `compiler/crc_model.py` (validated
  against the algorithms' published check values) and from RFC 1071. So both
  sides agree on the *algorithm* independently — but the comparison proves the
  generated hash gets the right operands in the right order, not that the
  algorithm your program names is the one you meant.
* **The model is an ideal table**; the hardware's exact-match table is
  hash-indexed and direct-mapped by default. Two entries whose keys collide
  cannot both be held unless the design was generated with
  `--exact-match-ways N`. A `FAIL` on a large entry set may be that, and it is
  a real limitation of the design rather than a bug in it.

## Constructs the model refuses today

| construct | why |
|---|---|
| `UserExtern` | its RTL is supplied by the user; its function is unknowable to a model |
| `Meter` | the generated debit bucket is implementation-defined, not a spec |
| multicast (`mcast_group`) | one packet in, several out; the model is a per-packet function |
| reading a `varbit` field as a value | the field has no fixed width to read; parsing and re-emitting one IS modelled (below) |
| a `varbit` that is not the last field of its header | placing it would need the following fixed widths subtracted first; no program here does it |
| header stacks | descoped in this compiler, so also in the model |

Each raises with the construct named. Extending the model is how that list
shrinks; the three apps in this repository that hit it are listed in
`docs/compiler_design.md`.

A runtime-length `extract(hdr.X, <bits>)` **is** modelled: the length
expression is evaluated against the fields parsed so far, that many bytes are
consumed, and the deparser emits the field back at the length it was parsed
with — which is what the design does by leaving those received bytes in place.
A length longer than the varbit's declared width is P4's `HeaderTooShort` and
the model rejects the packet, as the design does by saturating the same offset
at that width.

## Files

| file | role |
|---|---|
| `p4v.py` | the driver: compile, model, simulate, compare |
| `refmodel.py` | the reference model, over the compiler's IR |
| `expr.py` | evaluates the IR's expression strings, or refuses them by name |
| `pcap.py` | pcap read/write, and the text form the testbench reads |
| `build_ir.py` | builds the IR for an app with no RTL emission |
| `../../compiler/emit_vector_tb.py` | generates the file-driven testbench |
| `../vectors/` | this repository's own pcaps, regenerable by `make_vectors.py` |
