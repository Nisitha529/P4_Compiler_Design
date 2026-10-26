"""A reference model driven by the COMPILER'S OWN IR, so it covers any program
the compiler accepts -- not a per-application script.

What it is for: the testbenches in this project state expectations that a human
worked out by reading the P4. That checks the RTL against someone's reading of
the program. This checks it against an executable reading of the program, over
whatever traffic the designer supplies, for any program, with no new testbench
written per application.

What it is NOT: independent of the front end. It consumes the same IR the
emitters do, so a mis-INGESTED program is mis-modelled identically and the
comparison still passes. It therefore catches emitter and shell bugs -- which
is every bug this project has actually found in the datapath -- and not
ingestion bugs. Said plainly here because a framework that overstates its
coverage is the dangerous kind.

Honesty rule, enforced everywhere below: anything this model cannot represent
faithfully raises Unsupported, naming the construct. The driver then reports
that program NOT VERIFIED. It never approximates, because an approximate
oracle that reports PASS is worse than no oracle.

Semantics modelled (P4 semantics, not the shell's internal arrangement):
  parse      extract headers MSB-first from the frame, in parser-state order;
             a failed verify() drops the packet (what the shell does)
  ingress    tables (exact/lpm/ternary) -> action, assignments, if/else,
             setValid/setInvalid, drop, FeatureExport push, Register read/write
  egress     the same, run once per packet
  deparse    emit() the VALID headers in deparser order, then the bytes the
             parser did not consume -- so making a header valid that was never
             parsed lengthens the packet, and invalidating a parsed one
             shortens it
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', '..', 'compiler'))

import re                                                          # noqa: E402

from ir import (Assignment, ExternCall, IfStatement, TableApply)   # noqa: E402
# emit_top already splits a verify()'s "condition, error" pair and already
# knows which standard_metadata fields an architecture has. Imported rather
# than re-derived: a second implementation of either is a second thing to
# drift (the lesson from the self-test wrapper's duplicated port list).
from emit_top import _split_verify_args                            # noqa: E402
from crc_model import crc_of_bitvector, supported_algos             # noqa: E402
from expr import Evaluator, Unsupported                            # noqa: E402


class Entry:
    """One table entry, as the testcase file supplies it."""
    def __init__(self, action, keys=None, params=None, priority=0, masks=None,
                 prefix_len=None):
        self.action = action
        self.keys = keys or []
        self.params = params or {}
        self.priority = priority
        self.masks = masks
        self.prefix_len = prefix_len


class Result:
    def __init__(self, out_packet, std_meta, meta, records, dropped, truncated=False):
        self.out_packet = out_packet      # bytes, or None when dropped
        self.std_meta = std_meta
        self.meta = meta
        self.records = records            # [(feature_export_name, value)]
        self.dropped = dropped
        # True when the PARSER ran out of bytes (P4's PacketTooShort), as
        # distinct from the program choosing to drop. The generated design does
        # not implement PacketTooShort, so the two legitimately differ there
        # and the framework has to be able to say which kind of drop this was.
        self.truncated = truncated


class _Env:
    """Name resolution for the expression evaluator, over one packet's state."""

    def __init__(self, model, st, scope):
        self.m = model
        self.st = st
        self.scope = scope               # action params + local vars

    def lookup(self, path):
        if path in self.scope:
            return self.scope[path]
        if path.startswith('hdr.'):
            parts = path.split('.')
            if len(parts) != 3:
                raise Unsupported(f'header reference {path!r} is not hdr.<inst>.<field>')
            _, inst, field = parts
            w = self.m.field_width(inst, field)
            return self.st.hdr.get(inst, {}).get(field, 0), w
        if path.startswith('meta.'):
            name = path[len('meta.'):]
            if name not in self.m.meta_widths:
                raise Unsupported(f'unknown metadata field {path!r}')
            return self.st.meta.get(name, 0), self.m.meta_widths[name]
        if path.startswith('standard_metadata.'):
            name = path[len('standard_metadata.'):]
            if name not in self.m.std_widths:
                raise Unsupported(f'unknown standard_metadata field {path!r}')
            return self.st.std.get(name, 0), self.m.std_widths[name]
        raise Unsupported(f'unresolved name {path!r}')

    def is_valid(self, path):
        if not path.startswith('hdr.'):
            raise Unsupported(f'isValid() on {path!r}')
        return bool(self.st.valid.get(path.split('.', 1)[1], False))


class _State:
    def __init__(self):
        self.hdr = {}        # inst -> {field: value}
        self.valid = {}      # inst -> bool
        self.meta = {}
        self.std = {}
        self.records = []
        self.payload = b''
        self.parsed_bytes = 0


class Model:
    # Externs whose only effect is on state the packet comparison cannot see
    # (statistics). Modelled as no-ops DELIBERATELY, and listed here so the
    # choice is visible rather than buried in an `except`.
    _STAT_EXTERNS = ('count', 'count_bytes', 'count_packets')

    def __init__(self, ir):
        self.ir = ir
        self.inst = {h.inst_name: h for h in ir.header_instances if not h.is_stack}
        for h in ir.header_instances:
            if h.is_stack:
                raise Unsupported(
                    f'header stack {h.inst_name!r}: dynamic stacks are descoped in '
                    f'this compiler, so the model does not represent them either')
        self.meta_widths = {m.name: m.width for m in ir.metadata_fields}
        self.std_widths = dict(getattr(ir, 'std_meta_widths', {}) or {})
        if not self.std_widths:
            raise Unsupported(
                'the IR carries no standard_metadata widths -- that is the bmv2 '
                'front-end path, which has no top-level byte stream to compare')
        self.tables = {t.name: t for t in ir.tables}
        self.actions = {}
        for a in ir.actions:
            self.actions.setdefault(a.name, a)
        self.ctrl = ir.pipeline.ingress
        self.ectrl = ir.pipeline.egress
        if self.ectrl is not None and not (self.ectrl.tables or self.ectrl.statements):
            self.ectrl = None
        self.deparse_order = list(ir.pipeline.deparser.emit_list) if ir.pipeline.deparser else []
        self.last_match_order = None
        self.hit_truncation = False
        self.registers = {}
        for c in (self.ctrl, self.ectrl):
            for r in (getattr(c, 'registers', []) or []) if c else []:
                self.registers[r.name] = [0] * (r.size or 1)
        # Multicast: the shell replicates a packet to every member of its
        # group, so one input can produce several outputs. The model is a
        # per-packet function and does not represent that. Refused rather
        # than modelled-as-unicast, because unicast-when-it-should-replicate
        # would report PASS whenever the group happens to be empty.
        if self._writes_std(ir, 'mcast_group'):
            raise Unsupported(
                'the program writes standard_metadata.mcast_group: multicast '
                'replication produces several packets per input, which this '
                'per-packet model does not represent')
        self.fe_names = set()
        for c in (self.ctrl, self.ectrl):
            for fe in (getattr(c, 'feature_exports', []) or []) if c else []:
                self.fe_names.add(fe.name)
        self.hashes = {}
        for c in (self.ctrl, self.ectrl):
            for h in (getattr(c, 'hashes', []) or []) if c else []:
                if h.algo not in supported_algos():
                    raise Unsupported(
                        f'hash {h.name!r} uses algorithm {h.algo!r}, which '
                        f'crc_model.py does not implement')
                self.hashes[h.name] = h.algo

    @staticmethod
    def _writes_std(ir, field):
        tgt = f'standard_metadata.{field}'

        def scan(stmts):
            for s in stmts or []:
                if isinstance(s, Assignment) and s.lhs.split('[')[0] == tgt:
                    return True
                if isinstance(s, IfStatement) and (scan(s.then_body) or scan(s.else_body)):
                    return True
            return False

        if scan(getattr(ir.pipeline.ingress, 'statements', [])) or \
           scan(getattr(ir.pipeline.egress, 'statements', []) if ir.pipeline.egress else []):
            return True
        return any(scan(a.body) for a in ir.actions)

    # ---------------- layout ----------------
    def field_width(self, inst, field):
        h = self.inst.get(inst)
        if h is None:
            raise Unsupported(f'unknown header instance {inst!r}')
        for f in h.header_type.fields:
            if f.name == field:
                if f.is_varbit:
                    raise Unsupported(
                        f'varbit field hdr.{inst}.{field}: a variable-length field '
                        f'has no fixed layout for the model to serialise')
                return f.width
        raise Unsupported(f'unknown field hdr.{inst}.{field}')

    def header_bytes(self, inst):
        h = self.inst[inst]
        bits = sum(f.width for f in h.header_type.fields)
        if bits % 8:
            raise Unsupported(
                f'header {inst!r} is {bits} bits, not a byte multiple -- the '
                f'byte-stream model cannot place it')
        return bits // 8

    # ---------------- the run ----------------
    def run(self, packet, entries, ingress_port=0, timestamp=0):
        self.hit_truncation = False
        st = _State()
        st.std = {k: 0 for k in self.std_widths}
        if 'ingress_port' in st.std:
            st.std['ingress_port'] = ingress_port
        if 'packet_length' in st.std:
            st.std['packet_length'] = len(packet)
        if 'ingress_timestamp' in st.std:
            st.std['ingress_timestamp'] = timestamp
        st.meta = {m: 0 for m in self.meta_widths}
        for inst in self.inst:
            st.valid[inst] = False
            st.hdr[inst] = {f.name: 0 for f in self.inst[inst].header_type.fields}

        ok = self._parse(st, packet)
        if 'parsed_bytes' in st.std:
            st.std['parsed_bytes'] = st.parsed_bytes
        if not ok:
            # A failed verify() drops the packet in the generated shell; a
            # truncated extract SHOULD, per the spec, but does not here.
            return Result(None, st.std, st.meta, st.records, True,
                          truncated=self.hit_truncation)

        self._run_control(self.ctrl, st, entries)
        dropped = bool(st.std.get('drop', 0))
        if self.ectrl is not None:
            # Egress runs for a dropped packet too (the shell drives it on
            # dequeue with the sticky drop), which is what lets a program
            # export a feature for a packet it discarded.
            self._run_control(self.ectrl, st, entries)
            dropped = dropped or bool(st.std.get('drop', 0))
        if not dropped:
            self._checksums(st)
        out = None if dropped else self._deparse(st, packet)
        return Result(out, st.std, st.meta, st.records, dropped)

    # ---------------- update_checksum() ----------------
    @staticmethod
    def _csum16(bits, nbits):
        """The ones-complement 16-bit checksum: RFC 1071, which is what P4's
        HashAlgorithm.csum16 means. Implemented from the definition, not from
        the generated RTL -- a model that copied the implementation it is
        meant to check would agree with it by construction."""
        if nbits % 16:
            raise Unsupported(
                f'csum16 over {nbits} bits, which is not a whole number of '
                f'16-bit words')
        total = 0
        for i in range(nbits // 16 - 1, -1, -1):
            total += (bits >> (16 * i)) & 0xFFFF
        while total >> 16:
            total = (total & 0xFFFF) + (total >> 16)
        return (~total) & 0xFFFF

    def _checksums(self, st):
        for cu in getattr(self.ir, 'checksum_updates', []) or []:
            if cu.algo not in ('csum16', None):
                raise Unsupported(f'checksum algorithm {cu.algo!r} is not modelled')
            env = _Env(self, st, {})
            if cu.condition:
                ok, _ = Evaluator(env).eval(cu.condition)
                if not ok:
                    continue
            bits, nbits = 0, 0
            for fref in cu.fields:
                v, w = Evaluator(env).eval(fref)
                bits = (bits << w) | v
                nbits += w
            val = self._csum16(bits, nbits)
            if cu.dest_header not in self.inst:
                raise Unsupported(f'checksum destination hdr.{cu.dest_header} is unknown')
            w = self.field_width(cu.dest_header, cu.dest_field)
            st.hdr[cu.dest_header][cu.dest_field] = val & ((1 << w) - 1)

    # ---------------- parser ----------------
    def _parse(self, st, packet):
        state = self.ir.start_state or 'start'
        seen = set()
        off = 0
        while state not in ('accept', 'reject', None):
            if state in seen:
                raise Unsupported(f'parser loops through state {state!r}')
            seen.add(state)
            ps = self.ir.get_state(state)
            if ps is None:
                raise Unsupported(f'parser transitions to unknown state {state!r}')
            for ex in ps.extracts:
                if ex.dynamic:
                    raise Unsupported(
                        f'extract(hdr.{ex.header}) with a runtime length is not modelled')
                nb = self.header_bytes(ex.header)
                if off + nb > len(packet):
                    # P4's PacketTooShort: extract() needs more bytes than the
                    # packet has, the parser rejects, and in v1model the packet
                    # is dropped. Flagged separately because the generated
                    # design has no such check -- see the note on Result.
                    self.hit_truncation = True
                    return False
                self._place(st, ex.header, packet[off:off+nb])
                off += nb
                st.parsed_bytes = off
            env = _Env(self, st, {})
            ev = Evaluator(env)
            for vf in ps.verifies:
                cond, _err = _split_verify_args(vf.condition)
                v, _ = ev.eval(cond)
                if not v:
                    return False
            if ps.select is not None:
                key, kw = ev.eval(ps.select.expression)
                nxt = None
                for val, tgt in ps.select.cases:
                    cv, _ = Evaluator(env).eval(val) if not isinstance(val, int) else (val, kw)
                    if cv == key:
                        nxt = tgt
                        break
                state = nxt if nxt is not None else ps.select.default
                if state is None:
                    state = 'accept'
            else:
                state = ps.next_state or 'accept'
        return state != 'reject'

    def _place(self, st, inst, raw):
        """Deserialise a header's fields MSB-first out of `raw`."""
        acc = int.from_bytes(raw, 'big')
        total = len(raw) * 8
        pos = total
        for f in self.inst[inst].header_type.fields:
            if f.is_varbit:
                raise Unsupported(f'varbit field in hdr.{inst}')
            pos -= f.width
            st.hdr[inst][f.name] = (acc >> pos) & ((1 << f.width) - 1)
        st.valid[inst] = True

    # ---------------- controls ----------------
    def _run_control(self, ctrl, st, entries):
        if ctrl is None:
            return
        self._exec_block(ctrl.statements, ctrl, st, entries, {})

    def _exec_block(self, stmts, ctrl, st, entries, scope):
        for s in stmts:
            self._exec(s, ctrl, st, entries, scope)

    def _exec(self, s, ctrl, st, entries, scope):
        if isinstance(s, IfStatement):
            # `if (t.apply().hit)` APPLIES the table as part of evaluating the
            # condition -- the apply is not optional and its side effects
            # happen either way. So each one is run here, in the order it
            # appears, and the condition is rewritten with the result before
            # being evaluated.
            cond = s.condition
            for m in re.finditer(r'(\w+)\.apply\(\)\.(hit|miss)', s.condition):
                tname, which = m.group(1), m.group(2)
                hit = self._apply_table(tname, ctrl, st, entries)
                truth = hit if which == 'hit' else (not hit)
                cond = cond.replace(m.group(0), "1'd1" if truth else "1'd0")
            v, _ = Evaluator(_Env(self, st, scope)).eval(cond)
            self._exec_block(s.then_body if v else s.else_body, ctrl, st, entries, scope)
        elif isinstance(s, TableApply):
            self._apply_table(s.table_name, ctrl, st, entries)
        elif isinstance(s, Assignment):
            self._assign(st, scope, s.lhs, s.rhs)
        elif isinstance(s, ExternCall):
            self._extern(s, ctrl, st, entries, scope)
        elif s is None:
            return
        else:
            raise Unsupported(f'statement type {type(s).__name__} is not modelled')

    def _apply_table(self, name, ctrl, st, entries):
        """Apply one table. Returns True if an entry matched (its `.hit`)."""
        t = self.tables.get(name)
        if t is None:
            raise Unsupported(f'apply of unknown table {name!r}')
        row = self._match(t, st, entries.get(name, []))
        if row is None:
            dflt = t.default_action
            if dflt not in (None, 'NoAction'):
                self._run_action(dflt, {}, ctrl, st, entries)
            return False
        self._run_action(row.action, row.params, ctrl, st, entries)
        return True

    def _match(self, t, st, rows):
        env = _Env(self, st, {})
        kvals = []
        for k in t.keys:
            v, w = Evaluator(env).eval(k.field)
            kvals.append((v, w, k.match_type))
        # Resolution follows THE HARDWARE'S DOCUMENTED CONTRACT, which is not
        # the P4 specification's.
        #
        # emit_table.py builds an lpm/ternary table as an ordered array and
        # returns the LOWEST MATCHING INDEX; it does not compare prefix
        # lengths or mask widths. The cp_map says so in as many words:
        # "caller-ordered: insert MOST SPECIFIC first ... The hardware does not
        # sort and does not compare prefix lengths -- it returns the lowest
        # matching index."
        #
        # This model used to implement the spec's longest-prefix-wins instead,
        # and the randomised stimulus caught it immediately: entries
        # 10.0.0.7/8 then 10.0.0.237/16, a packet to 10.0.0.237, the model
        # picking /16 and the hardware /8. The hardware was right about its own
        # contract. An oracle has to check the design against the contract the
        # design states, so insertion order decides here too -- and
        # order_dependent() below is what warns a caller whose entry order
        # makes the two disagree.
        matches = []
        for idx, r in enumerate(rows):
            if len(r.keys) != len(kvals):
                raise Unsupported(
                    f'table {t.name!r} has {len(kvals)} key field(s) but an entry '
                    f'supplies {len(r.keys)}')
            ok, plen = True, 0
            for i, (v, w, mt) in enumerate(kvals):
                ek = r.keys[i]
                if mt == 'exact':
                    ok &= (ek == v)
                elif mt == 'lpm':
                    pl = r.prefix_len if r.prefix_len is not None else w
                    mask = 0 if pl == 0 else ((1 << w) - 1) ^ ((1 << (w - pl)) - 1)
                    ok &= ((ek & mask) == (v & mask))
                    plen += pl
                elif mt == 'ternary':
                    m = r.masks[i] if (r.masks and r.masks[i] is not None) else (1 << w) - 1
                    ok &= ((ek & m) == (v & m))
                    plen += bin(m).count('1')
                else:
                    raise Unsupported(f'match kind {mt!r} is not modelled')
                if not ok:
                    break
            if ok:
                matches.append((idx, plen, r))
        if not matches:
            return None
        self.last_match_order = matches      # order_dependent() reads this
        return matches[0][2]                 # lowest index wins

    def order_dependent(self, packet, entries, ingress_port=0):
        """Tables where this packet's entry order makes the hardware's
        lowest-index rule disagree with the P4 specification's
        longest-prefix/most-specific rule.

        This is a trap for a P4 programmer rather than a bug in the design: a
        program written expecting `lpm` to mean longest-prefix-match will
        behave differently here unless the control plane inserts the most
        specific entry first. Reported so it is a sentence, not a hex diff.
        """
        out = []
        for tname, rows in (entries or {}).items():
            t = self.tables.get(tname)
            if t is None or not any(k.match_type in ('lpm', 'ternary') for k in t.keys):
                continue
            kv = self.key_values(packet, tname, ingress_port)
            if kv is None:
                continue
            st = _State()
            st.std = {k: 0 for k in self.std_widths}
            st.meta = {m: 0 for m in self.meta_widths}
            for inst in self.inst:
                st.valid[inst] = False
                st.hdr[inst] = {f.name: 0 for f in self.inst[inst].header_type.fields}
            self._parse(st, packet)
            self.last_match_order = None
            self._match(t, st, rows)
            m = self.last_match_order
            if m and len(m) > 1:
                by_index = m[0]
                by_spec = max(m, key=lambda x: x[1])
                if by_index[0] != by_spec[0]:
                    out.append((tname, by_index, by_spec))
        return out

    def key_values(self, packet, table_name, ingress_port=0):
        """The key tuple `packet` presents to `table_name`: [(value, width)].

        Exists for the randomised stimulus generator. Generating random KEYS
        and hoping they match a table is hopeless -- a 16-bit exact key hits
        one time in 65536, so a fuzzer built that way would spend all its time
        on the miss path and never execute an action.

        Inverting it works: generate random PACKETS, ask the model what keys
        they present, and program entries for those values. That produces hits
        and misses in whatever mixture is wanted, and it needs no per-program
        knowledge, because the model is already evaluating the table's own key
        expressions.
        """
        t = self.tables.get(table_name)
        if t is None:
            raise Unsupported(f'unknown table {table_name!r}')
        st = _State()
        st.std = {k: 0 for k in self.std_widths}
        if 'ingress_port' in st.std:
            st.std['ingress_port'] = ingress_port
        if 'packet_length' in st.std:
            st.std['packet_length'] = len(packet)
        st.meta = {m: 0 for m in self.meta_widths}
        for inst in self.inst:
            st.valid[inst] = False
            st.hdr[inst] = {f.name: 0 for f in self.inst[inst].header_type.fields}
        if not self._parse(st, packet):
            return None              # the parser rejects it: no keys to speak of
        if 'parsed_bytes' in st.std:
            st.std['parsed_bytes'] = st.parsed_bytes
        env = _Env(self, st, {})
        out = []
        for k in t.keys:
            try:
                out.append(Evaluator(env).eval(k.field))
            except Unsupported:
                return None          # a key this model cannot evaluate
        return out

    def _run_action(self, name, params, ctrl, st, entries):
        a = self.actions.get(name)
        if a is None:
            if name == 'NoAction':
                return
            raise Unsupported(f'unknown action {name!r}')
        scope = {}
        for p in a.params:
            if p.name not in params:
                raise Unsupported(
                    f'action {name!r} needs parameter {p.name!r}, the entry does not supply it')
            scope[p.name] = (params[p.name] & ((1 << (p.width or 64)) - 1), p.width or 64)
        self._exec_block(a.body, ctrl, st, entries, scope)

    def _assign(self, st, scope, lhs, rhs):
        v, _ = Evaluator(_Env(self, st, scope)).eval(rhs)
        tgt, sl = lhs, None
        if tgt.endswith(']') and '[' in tgt:
            tgt, _, rest = tgt.partition('[')
            rest = rest[:-1]
            sl = tuple(int(x) for x in rest.split(':')) if ':' in rest else (int(rest), int(rest))
        if tgt.startswith('hdr.'):
            _, inst, field = tgt.split('.')
            w = self.field_width(inst, field)
            cur = st.hdr[inst][field]
            st.hdr[inst][field] = self._insert(cur, v, w, sl)
        elif tgt.startswith('meta.'):
            n = tgt[len('meta.'):]
            if n not in self.meta_widths:
                raise Unsupported(f'assignment to unknown metadata {tgt!r}')
            st.meta[n] = self._insert(st.meta.get(n, 0), v, self.meta_widths[n], sl)
        elif tgt.startswith('standard_metadata.'):
            n = tgt[len('standard_metadata.'):]
            if n not in self.std_widths:
                raise Unsupported(f'assignment to unknown standard_metadata {tgt!r}')
            st.std[n] = self._insert(st.std.get(n, 0), v, self.std_widths[n], sl)
        elif tgt in scope:
            w = scope[tgt][1]
            scope[tgt] = (self._insert(scope[tgt][0], v, w, sl), w)
        else:
            # A local variable declared in the control; width from the IR if
            # the ingester recorded it, otherwise refuse rather than guess.
            w = None
            for c in (self.ctrl, self.ectrl):
                for lv in (getattr(c, 'local_vars', []) or []) if c else []:
                    if lv.name == tgt:
                        w = lv.width
            if w is None:
                raise Unsupported(f'assignment to unknown target {lhs!r}')
            scope[tgt] = (self._insert(scope.get(tgt, (0, w))[0], v, w, sl), w)

    @staticmethod
    def _insert(cur, v, width, sl):
        if sl is None:
            return v & ((1 << width) - 1)
        hi, lo = sl
        nw = hi - lo + 1
        mask = ((1 << nw) - 1) << lo
        return ((cur & ~mask) | ((v & ((1 << nw) - 1)) << lo)) & ((1 << width) - 1)

    def _extern(self, s, ctrl, st, entries, scope):
        name, args = s.name, s.args
        base, _, meth = name.rpartition('.')
        if meth == 'setValid' and base.startswith('hdr.'):
            st.valid[base.split('.', 1)[1]] = True
            return
        if meth == 'setInvalid' and base.startswith('hdr.'):
            st.valid[base.split('.', 1)[1]] = False
            return
        if name == 'mark_to_drop' or meth == 'mark_to_drop':
            st.std['drop'] = 1
            return
        if meth == 'push' and base in self.fe_names:
            v, w = Evaluator(_Env(self, st, scope)).eval(args[0])
            st.records.append((base, v, w))
            return
        if meth in self._STAT_EXTERNS:
            return                      # statistics only: invisible to a packet diff
        if meth in ('clear', 'add', 'subtract', 'get'):
            # An InternetChecksum object's calls carry no value on their own,
            # in this model OR in the generated RTL: emit_processing writes a
            # comment for each and the real value comes from the program's
            # update_checksum() list (ir.checksum_updates). The model applies
            # that list after the controls, in _checksums(), for the same
            # reason -- the checksum has to see the FINAL header.
            return
        if meth == 'apply' and base in self.hashes:
            # Checksum<W>(HashAlgorithm_t.X).apply(result, f0, f1, ...): the
            # first argument is the OUT parameter (an out-param is a write --
            # the same rule that caused two silent table-never-matches in this
            # compiler), the rest are the data, concatenated MSB-first.
            #
            # Note what this does and does not check. The CRC comes from the
            # compiler's own crc_model.py, which is validated against the
            # algorithms' published check values -- so it is the ALGORITHM
            # that both sides agree on, not one copying the other's wiring.
            # What the comparison then proves is that the generated hash gets
            # the right operands, in the right order, at the right time; it
            # cannot prove the algorithm choice itself is what the designer
            # intended.
            e = Evaluator(_Env(self, st, scope))
            bits, nbits = 0, 0
            for arg in args[1:]:
                v, w = e.eval(arg)
                bits = (bits << w) | v
                nbits += w
            full = crc_of_bitvector(self.hashes[base], bits, nbits)
            self._assign(st, scope, args[0], str(full))
            return
        if meth == 'write' and base in self.registers:
            e = Evaluator(_Env(self, st, scope))
            idx, _ = e.eval(args[0])
            val, _ = e.eval(args[1])
            arr = self.registers[base]
            arr[idx % len(arr)] = val
            return
        if meth == 'read' and base in self.registers:
            e = Evaluator(_Env(self, st, scope))
            idx, _ = e.eval(args[1])
            arr = self.registers[base]
            self._assign(st, scope, args[0], f"{arr[idx % len(arr)]}")
            return
        raise Unsupported(f'extern call {name}({", ".join(args)}) is not modelled')

    # ---------------- deparser ----------------
    def _deparse(self, st, packet):
        out = bytearray()
        for inst in self.deparse_order:
            if inst not in self.inst:
                raise Unsupported(f'deparser emits unknown header {inst!r}')
            if not st.valid.get(inst):
                continue
            acc, bits = 0, 0
            for f in self.inst[inst].header_type.fields:
                if f.is_varbit:
                    raise Unsupported(f'varbit field in emitted hdr.{inst}')
                acc = (acc << f.width) | (st.hdr[inst][f.name] & ((1 << f.width) - 1))
                bits += f.width
            if bits % 8:
                raise Unsupported(f'emitted header {inst!r} is {bits} bits, not whole bytes')
            out += acc.to_bytes(bits // 8, 'big')
        # Everything the parser did not consume rides along unchanged.
        out += packet[st.parsed_bytes:]
        return bytes(out)
