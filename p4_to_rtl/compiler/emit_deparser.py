def emit_deparser(ir, output_path):
    """Generate deparser RTL from ir.pipeline.deparser.emit_list.

    Packs non-stack headers into a fixed-width output bus in emit order.
    Each header occupies a fixed slot (MSB-first); slot is zeroed when the
    header's valid flag is low.  Header stacks are excluded with a comment.
    """

    if not ir.pipeline.deparser or not ir.pipeline.deparser.emit_list:
        with open(output_path, 'w') as f:
            f.write('// deparser_generated.sv — no emit list in IR\n')
            f.write('module deparser_generated ();\nendmodule\n')
        return

    emit_list = ir.pipeline.deparser.emit_list
    inst_map  = {inst.inst_name: inst for inst in ir.header_instances}

    # ── Build ordered slot list, skip header stacks ──────────────────────
    hdr_slots   = []   # [(inst_name, Header type obj, total_width_bits)]
    stack_names = []

    for hname in emit_list:
        inst = inst_map.get(hname)
        if inst is None:
            continue
        if inst.is_stack:
            stack_names.append(hname)
            continue
        w = sum(fld.width or 0 for fld in inst.header_type.fields)
        if w == 0:
            continue
        hdr_slots.append((hname, inst.header_type, w))

    if not hdr_slots:
        with open(output_path, 'w') as f:
            f.write('// deparser_generated.sv — all emitted headers are stacks\n')
            f.write('module deparser_generated ();\nendmodule\n')
        return

    total_w   = sum(w for _, _, w in hdr_slots)
    hdr_names = [h for h, _, _ in hdr_slots]
    hdr_ports = [
        (hname, fld.name, fld.width)
        for hname, htype, _ in hdr_slots
        for fld in htype.fields
        if fld.width
    ]

    with open(output_path, 'w') as f:

        # ── Module declaration ────────────────────────────────────────────
        f.write('module deparser_generated (\n')
        f.write('  input  logic        clk,\n')
        f.write('  input  logic        rst_n,\n')
        f.write('  input  logic        valid_in,\n')

        f.write('\n  // Header valid flags\n')
        for hname in hdr_names:
            f.write(f'  input  logic        {hname}_valid,\n')

        f.write('\n  // Header field inputs\n')
        for hname, fname, w in hdr_ports:
            f.write(f'  input  logic [{w-1}:0] {hname}_{fname},\n')

        layout = ' | '.join(f'{h}({w}b)' for h, _, w in hdr_slots)
        f.write(f'\n  // Packed output [{total_w-1}:0]  layout (MSB first): {layout}\n')
        if stack_names:
            f.write(f'  // Stacks excluded: {", ".join(stack_names)}\n')
        f.write(f'  output logic [{total_w-1}:0] pkt_hdr_out,\n')
        f.write('  output logic [15:0]  pkt_hdr_len,\n')
        f.write('  output logic         valid_out\n')
        f.write(');\n\n')

        # ── Combinational packing ─────────────────────────────────────────
        f.write('  always_comb begin\n')
        f.write("    pkt_hdr_out = '0;\n")
        f.write('    pkt_hdr_len = 0;\n\n')

        bit_offset = total_w
        for hname, htype, w in hdr_slots:
            hi = bit_offset - 1
            lo = bit_offset - w
            fields_cat = ', '.join(
                f'{hname}_{fld.name}'
                for fld in htype.fields
                if fld.width
            )
            f.write(f'    if ({hname}_valid) begin\n')
            f.write(f'      pkt_hdr_out[{hi}:{lo}] = {{{fields_cat}}};\n')
            f.write(f'      pkt_hdr_len = pkt_hdr_len + 16\'d{w};\n')
            f.write('    end\n\n')
            bit_offset -= w

        f.write('  end\n\n')

        # ── Pipeline register ─────────────────────────────────────────────
        f.write('  always_ff @(posedge clk) begin\n')
        f.write('    if (!rst_n) valid_out <= 0;\n')
        f.write('    else        valid_out <= valid_in;\n')
        f.write('  end\n\n')

        f.write('endmodule\n')
