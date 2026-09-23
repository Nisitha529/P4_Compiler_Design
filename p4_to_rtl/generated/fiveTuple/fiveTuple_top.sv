module fiveTuple_top #(
    parameter int AXI_DATA_W  = 256,
    parameter int AXIL_ADDR_W = 16
) (
    input  logic clk,
    input  logic rst_n,

    // AXI4-Stream slave — packet in
    input  logic [AXI_DATA_W-1:0]    s_axis_tdata,
    input  logic [AXI_DATA_W/8-1:0]  s_axis_tkeep,
    input  logic                      s_axis_tvalid,
    output logic                      s_axis_tready,
    input  logic                      s_axis_tlast,

    // AXI4-Stream master — packet out
    output logic [AXI_DATA_W-1:0]    m_axis_tdata,
    output logic [AXI_DATA_W/8-1:0]  m_axis_tkeep,
    output logic                      m_axis_tvalid,
    input  logic                      m_axis_tready,
    output logic                      m_axis_tlast,

    // AXI4-Lite slave — table control plane
    input  logic [AXIL_ADDR_W-1:0]   s_axil_awaddr,
    input  logic                      s_axil_awvalid,
    output logic                      s_axil_awready,
    input  logic [31:0]               s_axil_wdata,
    input  logic [3:0]                s_axil_wstrb,
    input  logic                      s_axil_wvalid,
    output logic                      s_axil_wready,
    output logic [1:0]                s_axil_bresp,
    output logic                      s_axil_bvalid,
    input  logic                      s_axil_bready,
    input  logic [AXIL_ADDR_W-1:0]   s_axil_araddr,
    input  logic                      s_axil_arvalid,
    output logic                      s_axil_arready,
    output logic [31:0]               s_axil_rdata,
    output logic [1:0]                s_axil_rresp,
    output logic                      s_axil_rvalid,
    input  logic                      s_axil_rready
);

  localparam int BEAT_BYTES    = AXI_DATA_W / 8;  // 32
  localparam int MAX_PKT_BEATS = 256;
  localparam int MAX_PKT_BYTES = MAX_PKT_BEATS * BEAT_BYTES;  // 8192
  localparam int HDR_MAX_BYTES = 128;
  localparam int HDR_MAX_BEATS = 4;
  localparam int PAYLOAD_MAX_BYTES = MAX_PKT_BYTES - HDR_MAX_BYTES;  // 8064
  localparam int PAYLOAD_MAX_BEATS = PAYLOAD_MAX_BYTES / BEAT_BYTES;  // 252

  // ── Header slot ring ─────────────────────────────────────────────────────
  // NSLOT packets can be in flight at once. Each slot holds one packet's
  // header region (HDR_MAX_BYTES) as received, its per-row keep, its beat
  // count / done / overflow, and -- once the pipeline has finished with it --
  // the pipeline's output PHV, drop decision and metadata. Four pointers
  // walk the ring in order and never overtake each other:
  //   wr_ptr  : RX fills this slot          (advances on tlast)
  //   iss_ptr : next slot to issue to u_proc (advances on issue)
  //   cmp_ptr : next slot expecting a result (advances on out_valid)
  //   tx_ptr  : TX drains this slot         (advances on last beat / discard)
  // Each carries one extra bit so "full" and "empty" are distinguishable.
  // Payload beats do not live in slots: they stream through u_pfifo in
  // arrival order, and since every stage is in-order, the head of the FIFO
  // is always the first payload beat of the slot TX is on.
  localparam int NSLOT   = 4;
  localparam int SLOT_AW = 2;
  logic [7:0] slot_hdr [0:NSLOT*HDR_MAX_BYTES-1];
  logic [AXI_DATA_W/8-1:0] slot_keep [0:NSLOT*HDR_MAX_BEATS-1];
  logic [8:0] slot_beat_cnt [0:NSLOT-1];
  logic slot_done     [0:NSLOT-1];
  logic slot_overflow [0:NSLOT-1];
  logic [15:0] slot_byte_len [0:NSLOT-1];
  logic slot_drop     [0:NSLOT-1];
  logic slot_txdone   [0:NSLOT-1];   // TX has sent (or discarded) this slot
  logic tx_finish;    // driven in the TX section; read here to set slot_txdone
  `ifndef SYNTHESIS
  // synthesis translate_off
  initial begin
    for (int i = 0; i < NSLOT*HDR_MAX_BYTES; i++) slot_hdr[i] = 8'd0;
  end
  // synthesis translate_on
  `endif
  logic [SLOT_AW:0] wr_ptr, iss_ptr, rel_ptr;
  logic [SLOT_AW:0] cmp_ptr;   // no egress stage: completion is issue order
  wire  [SLOT_AW-1:0] wr_slot  = wr_ptr[SLOT_AW-1:0];
  wire  [SLOT_AW-1:0] iss_slot = iss_ptr[SLOT_AW-1:0];
  wire  [SLOT_AW-1:0] rel_slot = rel_ptr[SLOT_AW-1:0];

  // ── Traffic manager: per-queue slot FIFOs ────────────────────────────────
  // (this program has no egress control, so the scheduler degenerates:
  //  ingress completion feeds the transmit queue directly)
  logic [SLOT_AW-1:0] txq_mem [0:NSLOT-1];
  logic [SLOT_AW:0]   txq_wr, txq_rd;
  logic [SLOT_AW-1:0] cmp_slot;   // slot leaving the pipeline this cycle
  logic [SLOT_AW-1:0] tx_slot;    // slot TX is sending
  always_comb begin
    cmp_slot = cmp_ptr[SLOT_AW-1:0];
    tx_slot  = txq_mem[txq_rd[SLOT_AW-1:0]];
  end
  // rel_ptr: RELEASE pointer, trails tx_ptr. TX moving on (tx_ptr) and the
  // slot being reusable are different events: on an OVERSIZE packet the
  // FIFO entry marked last is pushed at MAX_PKT_BEATS while the link's real
  // tlast arrives later, so TX can finish while RX is still receiving into
  // the slot. Releasing then wiped the slot under RX and the remaining
  // beats were re-read as a new packet's header rows (deadlocked T8).
  // A slot is released only once its tlast has been seen.
  wire  [SLOT_AW:0] n_alloc  = wr_ptr - rel_ptr;
  wire  rx_slot_free = (n_alloc < NSLOT);

  // Header bytes of the slot being issued to the pipeline -- every w_* field
  // below is extracted from this. (Procedural mux, not continuous assigns
  // from array elements -- see the note at the extraction block.)
  logic [7:0] x_hdr [0:HDR_MAX_BYTES-1];
  always_comb for (int i = 0; i < HDR_MAX_BYTES; i++) x_hdr[i] = slot_hdr[iss_slot*HDR_MAX_BYTES + i];

  localparam int PFIFO_W  = AXI_DATA_W + AXI_DATA_W/8 + 1;  // {last, keep, data}
  localparam int PFIFO_AW = 8;
  localparam int PFIFO_DEPTH = 1 << PFIFO_AW;  // 256 >= PAYLOAD_MAX_BEATS
  logic [NSLOT-1:0]    pfifo_wr_en_v;
  logic [PFIFO_W-1:0]  pfifo_wr_data;   // shared: only slot wr_slot is written
  logic [NSLOT-1:0]    pfifo_full_v;
  logic [NSLOT-1:0]    pfifo_rd_valid_v;
  logic [PFIFO_W-1:0]  pfifo_rd_data_v [0:NSLOT-1];
  logic [NSLOT-1:0]    pfifo_rd_en_v;
  genvar gs;
  generate for (gs = 0; gs < NSLOT; gs++) begin : g_pfifo
    pkt_beat_fifo #(.W(PFIFO_W), .DEPTH(PFIFO_DEPTH), .AW(PFIFO_AW)) u_pfifo (
      .clk(clk), .rst_n(rst_n),
      .wr_en(pfifo_wr_en_v[gs]), .wr_data(pfifo_wr_data), .full(pfifo_full_v[gs]),
      .rd_valid(pfifo_rd_valid_v[gs]), .rd_data(pfifo_rd_data_v[gs]),
      .rd_en(pfifo_rd_en_v[gs]),
      .occupancy()
    );
  end endgenerate
  // Views of the slot each side is working on. Unpacked-array elements are
  // read in always_comb, never a continuous assign (iverilog 11 rejects the
  // latter -- the same rule the header extraction section follows).
  logic                pfifo_full;
  logic                pfifo_rd_valid;
  logic [PFIFO_W-1:0]  pfifo_rd_data;
  logic                pfifo_rd_en;
  logic                pfifo_wr_en;
  always_comb begin
    pfifo_full     = pfifo_full_v[wr_slot];
    pfifo_rd_valid = pfifo_rd_valid_v[tx_slot];
    pfifo_rd_data  = pfifo_rd_data_v[tx_slot];
    for (int sl = 0; sl < NSLOT; sl++) begin
      pfifo_wr_en_v[sl] = pfifo_wr_en && (wr_slot == sl[SLOT_AW-1:0]);
      pfifo_rd_en_v[sl] = pfifo_rd_en && (tx_slot == sl[SLOT_AW-1:0]);
    end
  end
  wire                  pfifo_head_last = pfifo_rd_data[PFIFO_W-1];
  wire [AXI_DATA_W/8-1:0] pfifo_head_keep = pfifo_rd_data[AXI_DATA_W +: AXI_DATA_W/8];
  wire [AXI_DATA_W-1:0]   pfifo_head_data = pfifo_rd_data[AXI_DATA_W-1:0];

  // ── State registers ──────────────────────────────────────────────────────
  //   iss_fire     : one-cycle valid_in pulse to u_proc for slot iss_slot
  //   proc_out_valid: u_proc's data-ALIGNED valid (out_valid port) -- the
  //                  cycle out_*/drop belong to slot cmp_slot
  //   tx_hdr_row/tx_in_payload: TX progress through slot tx_slot
  logic [8:0] tx_hdr_row;
  logic tx_in_payload;
  logic tx_out_valid;
  logic [255:0] tx_out_data;
  logic [31:0] tx_out_keep;
  logic tx_out_last;

  // ── Header field extraction from pkt_buf ────────────────────────────────
  //    Fields extracted using big-endian (network byte order) bit mapping.

  // eth — base: 0
  logic [47:0] w_eth_dmac;
  logic [47:0] w_eth_smac;
  logic [15:0] w_eth_type;
  always_comb begin
    w_eth_dmac = {x_hdr[0], x_hdr[1], x_hdr[2], x_hdr[3], x_hdr[4], x_hdr[5]};
    w_eth_smac = {x_hdr[6], x_hdr[7], x_hdr[8], x_hdr[9], x_hdr[10], x_hdr[11]};
    w_eth_type = {x_hdr[12], x_hdr[13]};
  end

  // vlan — base: 14
  logic [2:0] w_vlan_pcp;
  logic [0:0] w_vlan_cfi;
  logic [11:0] w_vlan_vid;
  logic [15:0] w_vlan_tpid;
  always_comb begin
    w_vlan_pcp = x_hdr[14][7:5];
    w_vlan_cfi = x_hdr[14][4:4];
    w_vlan_vid = {x_hdr[14][3:0], x_hdr[14+1]};
    w_vlan_tpid = {x_hdr[14+2], x_hdr[14+3]};
  end

  wire [13:0] w_ipv4_base = 14 + ((w_eth_type == 16'h8100) ? 4 : 0);
  // ipv4 — base: w_ipv4_base
  logic [3:0] w_ipv4_version;
  logic [3:0] w_ipv4_hdr_len;
  logic [7:0] w_ipv4_tos;
  logic [15:0] w_ipv4_length;
  logic [15:0] w_ipv4_id;
  logic [2:0] w_ipv4_flags;
  logic [12:0] w_ipv4_offset;
  logic [7:0] w_ipv4_ttl;
  logic [7:0] w_ipv4_protocol;
  logic [15:0] w_ipv4_hdr_chk;
  logic [31:0] w_ipv4_src;
  logic [31:0] w_ipv4_dst;
  always_comb begin
    w_ipv4_version = x_hdr[w_ipv4_base][7:4];
    w_ipv4_hdr_len = x_hdr[w_ipv4_base][3:0];
    w_ipv4_tos = x_hdr[w_ipv4_base+1];
    w_ipv4_length = {x_hdr[w_ipv4_base+2], x_hdr[w_ipv4_base+3]};
    w_ipv4_id = {x_hdr[w_ipv4_base+4], x_hdr[w_ipv4_base+5]};
    w_ipv4_flags = x_hdr[w_ipv4_base+6][7:5];
    w_ipv4_offset = {x_hdr[w_ipv4_base+6][4:0], x_hdr[w_ipv4_base+7]};
    w_ipv4_ttl = x_hdr[w_ipv4_base+8];
    w_ipv4_protocol = x_hdr[w_ipv4_base+9];
    w_ipv4_hdr_chk = {x_hdr[w_ipv4_base+10], x_hdr[w_ipv4_base+11]};
    w_ipv4_src = {x_hdr[w_ipv4_base+12], x_hdr[w_ipv4_base+13], x_hdr[w_ipv4_base+14], x_hdr[w_ipv4_base+15]};
    w_ipv4_dst = {x_hdr[w_ipv4_base+16], x_hdr[w_ipv4_base+17], x_hdr[w_ipv4_base+18], x_hdr[w_ipv4_base+19]};
  end

  wire [13:0] w_ipv4_hdr_bytes = {10'b0, w_ipv4_hdr_len} << 2;
  wire [13:0] w_ipv4opt_base = w_ipv4_base + w_ipv4_hdr_bytes;
  // ipv4opt — base: w_ipv4opt_base
  logic [319:0] w_ipv4opt_options;
  always_comb begin
    w_ipv4opt_options = {x_hdr[w_ipv4opt_base], x_hdr[w_ipv4opt_base+1], x_hdr[w_ipv4opt_base+2], x_hdr[w_ipv4opt_base+3], x_hdr[w_ipv4opt_base+4], x_hdr[w_ipv4opt_base+5], x_hdr[w_ipv4opt_base+6], x_hdr[w_ipv4opt_base+7], x_hdr[w_ipv4opt_base+8], x_hdr[w_ipv4opt_base+9], x_hdr[w_ipv4opt_base+10], x_hdr[w_ipv4opt_base+11], x_hdr[w_ipv4opt_base+12], x_hdr[w_ipv4opt_base+13], x_hdr[w_ipv4opt_base+14], x_hdr[w_ipv4opt_base+15], x_hdr[w_ipv4opt_base+16], x_hdr[w_ipv4opt_base+17], x_hdr[w_ipv4opt_base+18], x_hdr[w_ipv4opt_base+19], x_hdr[w_ipv4opt_base+20], x_hdr[w_ipv4opt_base+21], x_hdr[w_ipv4opt_base+22], x_hdr[w_ipv4opt_base+23], x_hdr[w_ipv4opt_base+24], x_hdr[w_ipv4opt_base+25], x_hdr[w_ipv4opt_base+26], x_hdr[w_ipv4opt_base+27], x_hdr[w_ipv4opt_base+28], x_hdr[w_ipv4opt_base+29], x_hdr[w_ipv4opt_base+30], x_hdr[w_ipv4opt_base+31], x_hdr[w_ipv4opt_base+32], x_hdr[w_ipv4opt_base+33], x_hdr[w_ipv4opt_base+34], x_hdr[w_ipv4opt_base+35], x_hdr[w_ipv4opt_base+36], x_hdr[w_ipv4opt_base+37], x_hdr[w_ipv4opt_base+38], x_hdr[w_ipv4opt_base+39]};
  end

  wire [13:0] w_tcp_base = w_ipv4_base + w_ipv4_hdr_bytes;
  // tcp — base: w_tcp_base
  logic [15:0] w_tcp_src_port;
  logic [15:0] w_tcp_dst_port;
  logic [31:0] w_tcp_seqNum;
  logic [31:0] w_tcp_ackNum;
  logic [3:0] w_tcp_dataOffset;
  logic [5:0] w_tcp_resv;
  logic [5:0] w_tcp_flags;
  logic [15:0] w_tcp_window;
  logic [15:0] w_tcp_checksum;
  logic [15:0] w_tcp_urgPtr;
  always_comb begin
    w_tcp_src_port = {x_hdr[w_tcp_base], x_hdr[w_tcp_base+1]};
    w_tcp_dst_port = {x_hdr[w_tcp_base+2], x_hdr[w_tcp_base+3]};
    w_tcp_seqNum = {x_hdr[w_tcp_base+4], x_hdr[w_tcp_base+5], x_hdr[w_tcp_base+6], x_hdr[w_tcp_base+7]};
    w_tcp_ackNum = {x_hdr[w_tcp_base+8], x_hdr[w_tcp_base+9], x_hdr[w_tcp_base+10], x_hdr[w_tcp_base+11]};
    w_tcp_dataOffset = x_hdr[w_tcp_base+12][7:4];
    w_tcp_resv = {x_hdr[w_tcp_base+12][3:0], x_hdr[w_tcp_base+13][7:6]};
    w_tcp_flags = x_hdr[w_tcp_base+13][5:0];
    w_tcp_window = {x_hdr[w_tcp_base+14], x_hdr[w_tcp_base+15]};
    w_tcp_checksum = {x_hdr[w_tcp_base+16], x_hdr[w_tcp_base+17]};
    w_tcp_urgPtr = {x_hdr[w_tcp_base+18], x_hdr[w_tcp_base+19]};
  end

  wire [13:0] w_tcpopt_base = w_ipv4_base + w_ipv4_hdr_bytes;
  // tcpopt — base: w_tcpopt_base
  logic [319:0] w_tcpopt_options;
  always_comb begin
    w_tcpopt_options = {x_hdr[w_tcpopt_base], x_hdr[w_tcpopt_base+1], x_hdr[w_tcpopt_base+2], x_hdr[w_tcpopt_base+3], x_hdr[w_tcpopt_base+4], x_hdr[w_tcpopt_base+5], x_hdr[w_tcpopt_base+6], x_hdr[w_tcpopt_base+7], x_hdr[w_tcpopt_base+8], x_hdr[w_tcpopt_base+9], x_hdr[w_tcpopt_base+10], x_hdr[w_tcpopt_base+11], x_hdr[w_tcpopt_base+12], x_hdr[w_tcpopt_base+13], x_hdr[w_tcpopt_base+14], x_hdr[w_tcpopt_base+15], x_hdr[w_tcpopt_base+16], x_hdr[w_tcpopt_base+17], x_hdr[w_tcpopt_base+18], x_hdr[w_tcpopt_base+19], x_hdr[w_tcpopt_base+20], x_hdr[w_tcpopt_base+21], x_hdr[w_tcpopt_base+22], x_hdr[w_tcpopt_base+23], x_hdr[w_tcpopt_base+24], x_hdr[w_tcpopt_base+25], x_hdr[w_tcpopt_base+26], x_hdr[w_tcpopt_base+27], x_hdr[w_tcpopt_base+28], x_hdr[w_tcpopt_base+29], x_hdr[w_tcpopt_base+30], x_hdr[w_tcpopt_base+31], x_hdr[w_tcpopt_base+32], x_hdr[w_tcpopt_base+33], x_hdr[w_tcpopt_base+34], x_hdr[w_tcpopt_base+35], x_hdr[w_tcpopt_base+36], x_hdr[w_tcpopt_base+37], x_hdr[w_tcpopt_base+38], x_hdr[w_tcpopt_base+39]};
  end

  wire [13:0] w_udp_base = w_ipv4_base + w_ipv4_hdr_bytes;
  // udp — base: w_udp_base
  logic [15:0] w_udp_src_port;
  logic [15:0] w_udp_dst_port;
  logic [15:0] w_udp_length;
  logic [15:0] w_udp_checksum;
  always_comb begin
    w_udp_src_port = {x_hdr[w_udp_base], x_hdr[w_udp_base+1]};
    w_udp_dst_port = {x_hdr[w_udp_base+2], x_hdr[w_udp_base+3]};
    w_udp_length = {x_hdr[w_udp_base+4], x_hdr[w_udp_base+5]};
    w_udp_checksum = {x_hdr[w_udp_base+6], x_hdr[w_udp_base+7]};
  end

  // ── Header validity (derived from extracted fields) ──────────────────────
  wire w_eth_valid = 1'b1;
  wire w_vlan_valid = (w_eth_type == 16'h8100);
  wire w_ipv4_valid = ((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800)));
  wire w_ipv4opt_valid = ((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800)));
  wire w_tcp_valid = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h06)) && (w_ipv4_version == 4'd4 && w_ipv4_hdr_len >= 4'd5));
  wire w_tcpopt_valid = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h06)) && (w_ipv4_version == 4'd4 && w_ipv4_hdr_len >= 4'd5));
  wire w_udp_valid = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h11)) && (w_ipv4_version == 4'd4 && w_ipv4_hdr_len >= 4'd5));
  wire w_new_vlan_valid = 1'b0;

  // ── standard_metadata.parser_error (from parser verify()) ────────────────
  wire [3:0] w_parser_error = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800)))) && !(w_ipv4_version == 4'd4 && w_ipv4_hdr_len >= 4'd5)) ? 4'd8 : ((((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h06)) && (w_ipv4_version == 4'd4 && w_ipv4_hdr_len >= 4'd5))) && !(w_tcp_dataOffset >= 4'd5)) ? 4'd9 : 4'd0;

  // ── Header-region cutoff ──────────────────────────────────────────────────
  wire [13:0] w_eth_cutoff_term = 0 + 14;
  wire [13:0] w_vlan_cutoff_term = (w_eth_type == 16'h8100) ? (14 + 4) : 14'd0;
  wire [13:0] w_ipv4_cutoff_term = ((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) ? (w_ipv4_base + 20) : 14'd0;
  wire [13:0] w_ipv4opt_cutoff_term = ((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) ? (w_ipv4opt_base + 40) : 14'd0;
  wire [13:0] w_tcp_cutoff_term = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h06)) && (w_ipv4_version == 4'd4 && w_ipv4_hdr_len >= 4'd5)) ? (w_tcp_base + 20) : 14'd0;
  wire [13:0] w_tcpopt_cutoff_term = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h06)) && (w_ipv4_version == 4'd4 && w_ipv4_hdr_len >= 4'd5)) ? (w_tcpopt_base + 40) : 14'd0;
  wire [13:0] w_udp_cutoff_term = ((((w_eth_type == 16'h0800) || ((w_eth_type == 16'h8100) && (w_vlan_tpid == 16'h0800))) && (w_ipv4_protocol == 8'h11)) && (w_ipv4_version == 4'd4 && w_ipv4_hdr_len >= 4'd5)) ? (w_udp_base + 8) : 14'd0;
  wire [13:0] w_cutoff_max_1 = (w_eth_cutoff_term > w_vlan_cutoff_term) ? w_eth_cutoff_term : w_vlan_cutoff_term;
  wire [13:0] w_cutoff_max_2 = (w_cutoff_max_1 > w_ipv4_cutoff_term) ? w_cutoff_max_1 : w_ipv4_cutoff_term;
  wire [13:0] w_cutoff_max_3 = (w_cutoff_max_2 > w_ipv4opt_cutoff_term) ? w_cutoff_max_2 : w_ipv4opt_cutoff_term;
  wire [13:0] w_cutoff_max_4 = (w_cutoff_max_3 > w_tcp_cutoff_term) ? w_cutoff_max_3 : w_tcp_cutoff_term;
  wire [13:0] w_cutoff_max_5 = (w_cutoff_max_4 > w_tcpopt_cutoff_term) ? w_cutoff_max_4 : w_tcpopt_cutoff_term;
  wire [13:0] w_cutoff_max_6 = (w_cutoff_max_5 > w_udp_cutoff_term) ? w_cutoff_max_5 : w_udp_cutoff_term;
  wire [13:0] cutoff_byte = w_cutoff_max_6;

  // Action-only headers (not in received packet; inputs tied to 0)
  wire [2:0] w_new_vlan_pcp = '0;
  wire [0:0] w_new_vlan_cfi = '0;
  wire [11:0] w_new_vlan_vid = '0;
  wire [15:0] w_new_vlan_tpid = '0;

  // ── processing_generated ─────────────────────────────────────────────────
  //    Signals prefixed proc_out_* are the match-action outputs.

  wire out_eth_valid;
  wire [47:0] out_eth_dmac;
  wire [47:0] out_eth_smac;
  wire [15:0] out_eth_type;
  wire out_vlan_valid;
  wire [2:0] out_vlan_pcp;
  wire [0:0] out_vlan_cfi;
  wire [11:0] out_vlan_vid;
  wire [15:0] out_vlan_tpid;
  wire out_ipv4_valid;
  wire [3:0] out_ipv4_version;
  wire [3:0] out_ipv4_hdr_len;
  wire [7:0] out_ipv4_tos;
  wire [15:0] out_ipv4_length;
  wire [15:0] out_ipv4_id;
  wire [2:0] out_ipv4_flags;
  wire [12:0] out_ipv4_offset;
  wire [7:0] out_ipv4_ttl;
  wire [7:0] out_ipv4_protocol;
  wire [15:0] out_ipv4_hdr_chk;
  wire [31:0] out_ipv4_src;
  wire [31:0] out_ipv4_dst;
  wire out_ipv4opt_valid;
  wire [319:0] out_ipv4opt_options;
  wire out_tcp_valid;
  wire [15:0] out_tcp_src_port;
  wire [15:0] out_tcp_dst_port;
  wire [31:0] out_tcp_seqNum;
  wire [31:0] out_tcp_ackNum;
  wire [3:0] out_tcp_dataOffset;
  wire [5:0] out_tcp_resv;
  wire [5:0] out_tcp_flags;
  wire [15:0] out_tcp_window;
  wire [15:0] out_tcp_checksum;
  wire [15:0] out_tcp_urgPtr;
  wire out_tcpopt_valid;
  wire [319:0] out_tcpopt_options;
  wire out_udp_valid;
  wire [15:0] out_udp_src_port;
  wire [15:0] out_udp_dst_port;
  wire [15:0] out_udp_length;
  wire [15:0] out_udp_checksum;
  wire out_new_vlan_valid;
  wire [2:0] out_new_vlan_pcp;
  wire [0:0] out_new_vlan_cfi;
  wire [11:0] out_new_vlan_vid;
  wire [15:0] out_new_vlan_tpid;
  wire proc_valid_out;
  wire proc_out_valid;
  wire proc_drop;
  logic iss_fire;

  wire FiveTuple_cp_query_busy;
  wire FiveTuple_cp_query_hit;
  wire [0:0] FiveTuple_cp_query_action_id;
  wire [12:0] FiveTuple_cp_query_p_counter_index;
  wire [2:0] FiveTuple_cp_query_p_pcp;
  wire [0:0] FiveTuple_cp_query_p_cfi;
  wire [11:0] FiveTuple_cp_query_p_vid;
  wire PacketCounter_cp_query_busy;
  wire [63:0] PacketCounter_cp_query_pkt_value;
  wire ByteCounter_cp_query_busy;
  wire [63:0] ByteCounter_cp_query_byte_value;


  // ── AXI4-Lite staging registers ─────────────────────────────────────────
  logic [12:0] r_FiveTuple_cp_wr_idx;
  logic [0:0] r_FiveTuple_cp_wr_action;
  logic [31:0] r_FiveTuple_cp_wr_key_src;
  logic [31:0] r_FiveTuple_cp_wr_key_dst;
  logic [7:0] r_FiveTuple_cp_wr_key_protocol;
  logic [15:0] r_FiveTuple_cp_wr_key_table_key_sport;
  logic [15:0] r_FiveTuple_cp_wr_key_table_key_dport;
  logic [12:0] r_FiveTuple_cp_wr_p_counter_index;
  logic [2:0] r_FiveTuple_cp_wr_p_pcp;
  logic [0:0] r_FiveTuple_cp_wr_p_cfi;
  logic [11:0] r_FiveTuple_cp_wr_p_vid;
  logic [31:0] r_FiveTuple_cp_query_key_src;
  logic [31:0] r_FiveTuple_cp_query_key_dst;
  logic [7:0] r_FiveTuple_cp_query_key_protocol;
  logic [15:0] r_FiveTuple_cp_query_key_table_key_sport;
  logic [15:0] r_FiveTuple_cp_query_key_table_key_dport;
  logic r_FiveTuple_cp_query_del;
  logic [12:0] r_PacketCounter_cp_query_idx;
  logic [12:0] r_ByteCounter_cp_query_idx;
  logic r_FiveTuple_cp_wr_en;
  logic r_FiveTuple_cp_query_en;
  logic r_PacketCounter_cp_wr_en;
  logic r_PacketCounter_cp_query_en;
  logic r_ByteCounter_cp_wr_en;
  logic r_ByteCounter_cp_query_en;

  // AXI4-Lite write channel state machine
  typedef enum logic [1:0] {
    AXIL_IDLE  = 2'd0,
    AXIL_WDATA = 2'd1,
    AXIL_BRESP = 2'd2
  } axil_st_t;

  axil_st_t               axil_st;
  logic [AXIL_ADDR_W-1:0] axil_awaddr_r;

  assign s_axil_awready = (axil_st == AXIL_IDLE);
  assign s_axil_bvalid  = (axil_st == AXIL_BRESP);
  assign s_axil_bresp   = 2'b00;

  // Commit-type words for a busy table stall wready instead of silently
  // dropping the write (see cp_query_busy on the query/delete pipeline).
  logic pending_commit_busy;
  always @(*) begin
    pending_commit_busy = 1'b0;
    case (axil_awaddr_r[AXIL_ADDR_W-1:2])
      14'd11: pending_commit_busy = FiveTuple_cp_query_busy;
      14'd17: pending_commit_busy = FiveTuple_cp_query_busy;
      14'd18: pending_commit_busy = FiveTuple_cp_query_busy;
      14'd65: pending_commit_busy = PacketCounter_cp_query_busy;
      14'd129: pending_commit_busy = ByteCounter_cp_query_busy;
      default: pending_commit_busy = 1'b0;
    endcase
  end
  assign s_axil_wready = (axil_st == AXIL_WDATA) && !pending_commit_busy;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil_st <= AXIL_IDLE;
      r_FiveTuple_cp_wr_en <= 1'b0;
      r_FiveTuple_cp_query_en <= 1'b0;
      r_PacketCounter_cp_wr_en <= 1'b0;
      r_PacketCounter_cp_query_en <= 1'b0;
      r_ByteCounter_cp_wr_en <= 1'b0;
      r_ByteCounter_cp_query_en <= 1'b0;
    end else begin
      r_FiveTuple_cp_wr_en <= 1'b0;
      r_FiveTuple_cp_query_en <= 1'b0;
      r_PacketCounter_cp_wr_en <= 1'b0;
      r_PacketCounter_cp_query_en <= 1'b0;
      r_ByteCounter_cp_wr_en <= 1'b0;
      r_ByteCounter_cp_query_en <= 1'b0;
      case (axil_st)
        AXIL_IDLE: begin
          if (s_axil_awvalid) begin
            axil_awaddr_r <= s_axil_awaddr;
            axil_st       <= AXIL_WDATA;
          end
        end
        AXIL_WDATA: begin
          if (s_axil_wvalid && s_axil_wready) begin
            case (axil_awaddr_r[AXIL_ADDR_W-1:2])  // word address
              14'd0: r_FiveTuple_cp_wr_idx <= s_axil_wdata[12:0]; // wr_idx
              14'd1: r_FiveTuple_cp_wr_action <= s_axil_wdata[0:0]; // wr_action
              14'd2: r_FiveTuple_cp_wr_key_src <= s_axil_wdata[31:0]; // key_src
              14'd3: r_FiveTuple_cp_wr_key_dst <= s_axil_wdata[31:0]; // key_dst
              14'd4: r_FiveTuple_cp_wr_key_protocol <= s_axil_wdata[7:0]; // key_protocol
              14'd5: r_FiveTuple_cp_wr_key_table_key_sport <= s_axil_wdata[15:0]; // key_table_key_sport
              14'd6: r_FiveTuple_cp_wr_key_table_key_dport <= s_axil_wdata[15:0]; // key_table_key_dport
              14'd7: r_FiveTuple_cp_wr_p_counter_index <= s_axil_wdata[12:0]; // p_counter_index
              14'd8: r_FiveTuple_cp_wr_p_pcp <= s_axil_wdata[2:0]; // p_pcp
              14'd9: r_FiveTuple_cp_wr_p_cfi <= s_axil_wdata[0:0]; // p_cfi
              14'd10: r_FiveTuple_cp_wr_p_vid <= s_axil_wdata[11:0]; // p_vid
              14'd11: r_FiveTuple_cp_wr_en <= 1'b1; // FiveTuple commit
              14'd12: r_FiveTuple_cp_query_key_src <= s_axil_wdata[31:0]; // query_key_src
              14'd13: r_FiveTuple_cp_query_key_dst <= s_axil_wdata[31:0]; // query_key_dst
              14'd14: r_FiveTuple_cp_query_key_protocol <= s_axil_wdata[7:0]; // query_key_protocol
              14'd15: r_FiveTuple_cp_query_key_table_key_sport <= s_axil_wdata[15:0]; // query_key_table_key_sport
              14'd16: r_FiveTuple_cp_query_key_table_key_dport <= s_axil_wdata[15:0]; // query_key_table_key_dport
              14'd17: begin r_FiveTuple_cp_query_en <= 1'b1; r_FiveTuple_cp_query_del <= 1'b0; end // FiveTuple query
              14'd18: begin r_FiveTuple_cp_query_en <= 1'b1; r_FiveTuple_cp_query_del <= 1'b1; end // FiveTuple delete
              14'd64: r_PacketCounter_cp_query_idx <= s_axil_wdata[12:0]; // query_idx
              14'd65: r_PacketCounter_cp_query_en <= 1'b1; // PacketCounter query
              14'd128: r_ByteCounter_cp_query_idx <= s_axil_wdata[12:0]; // query_idx
              14'd129: r_ByteCounter_cp_query_en <= 1'b1; // ByteCounter query
              default: ; // ignore unknown address
            endcase
            axil_st <= AXIL_BRESP;
          end
        end
        AXIL_BRESP: begin
          if (s_axil_bready) axil_st <= AXIL_IDLE;
        end
        default: axil_st <= AXIL_IDLE;
      endcase
    end
  end

  // AXI4-Lite read channel
  typedef enum logic {
    AXIL_R_IDLE = 1'd0,
    AXIL_R_DATA = 1'd1
  } axil_rst_t;

  axil_rst_t   axil_rst;
  logic [31:0] r_rdata;

  assign s_axil_arready = (axil_rst == AXIL_R_IDLE);
  assign s_axil_rdata   = r_rdata;
  assign s_axil_rresp   = 2'b00;
  assign s_axil_rvalid  = (axil_rst == AXIL_R_DATA);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      axil_rst <= AXIL_R_IDLE;
    end else begin
      case (axil_rst)
        AXIL_R_IDLE: begin
          if (s_axil_arvalid) begin
            case (s_axil_araddr[AXIL_ADDR_W-1:2])  // word address
              14'd19: r_rdata <= {30'd0, FiveTuple_cp_query_hit, FiveTuple_cp_query_busy}; // FiveTuple query_status
              14'd20: r_rdata <= {31'd0, FiveTuple_cp_query_action_id}; // FiveTuple query_action_id
              14'd21: r_rdata <= {19'd0, FiveTuple_cp_query_p_counter_index}; // FiveTuple query_p_counter_index
              14'd22: r_rdata <= {29'd0, FiveTuple_cp_query_p_pcp}; // FiveTuple query_p_pcp
              14'd23: r_rdata <= {31'd0, FiveTuple_cp_query_p_cfi}; // FiveTuple query_p_cfi
              14'd24: r_rdata <= {20'd0, FiveTuple_cp_query_p_vid}; // FiveTuple query_p_vid
              14'd66: r_rdata <= {31'd0, PacketCounter_cp_query_busy}; // PacketCounter query_status
              14'd67: r_rdata <= PacketCounter_cp_query_pkt_value[31:0]; // PacketCounter value_pkt_lo
              14'd68: r_rdata <= PacketCounter_cp_query_pkt_value[63:32]; // PacketCounter value_pkt_hi
              14'd130: r_rdata <= {31'd0, ByteCounter_cp_query_busy}; // ByteCounter query_status
              14'd131: r_rdata <= ByteCounter_cp_query_byte_value[31:0]; // ByteCounter value_byte_lo
              14'd132: r_rdata <= ByteCounter_cp_query_byte_value[63:32]; // ByteCounter value_byte_hi
              default: r_rdata <= 32'd0;
            endcase
            axil_rst <= AXIL_R_DATA;
          end
        end
        AXIL_R_DATA: begin
          if (s_axil_rready) axil_rst <= AXIL_R_IDLE;
        end
        default: axil_rst <= AXIL_R_IDLE;
      endcase
    end
  end

  wire [12:0] FiveTuple_cp_wr_idx = r_FiveTuple_cp_wr_idx;
  wire [0:0] FiveTuple_cp_wr_action = r_FiveTuple_cp_wr_action;
  wire [31:0] FiveTuple_cp_wr_key_src = r_FiveTuple_cp_wr_key_src;
  wire [31:0] FiveTuple_cp_wr_key_dst = r_FiveTuple_cp_wr_key_dst;
  wire [7:0] FiveTuple_cp_wr_key_protocol = r_FiveTuple_cp_wr_key_protocol;
  wire [15:0] FiveTuple_cp_wr_key_table_key_sport = r_FiveTuple_cp_wr_key_table_key_sport;
  wire [15:0] FiveTuple_cp_wr_key_table_key_dport = r_FiveTuple_cp_wr_key_table_key_dport;
  wire [12:0] FiveTuple_cp_wr_p_counter_index = r_FiveTuple_cp_wr_p_counter_index;
  wire [2:0] FiveTuple_cp_wr_p_pcp = r_FiveTuple_cp_wr_p_pcp;
  wire [0:0] FiveTuple_cp_wr_p_cfi = r_FiveTuple_cp_wr_p_cfi;
  wire [11:0] FiveTuple_cp_wr_p_vid = r_FiveTuple_cp_wr_p_vid;
  wire FiveTuple_cp_wr_en = r_FiveTuple_cp_wr_en;
  wire [31:0] FiveTuple_cp_query_key_src = r_FiveTuple_cp_query_key_src;
  wire [31:0] FiveTuple_cp_query_key_dst = r_FiveTuple_cp_query_key_dst;
  wire [7:0] FiveTuple_cp_query_key_protocol = r_FiveTuple_cp_query_key_protocol;
  wire [15:0] FiveTuple_cp_query_key_table_key_sport = r_FiveTuple_cp_query_key_table_key_sport;
  wire [15:0] FiveTuple_cp_query_key_table_key_dport = r_FiveTuple_cp_query_key_table_key_dport;
  wire FiveTuple_cp_query_en  = r_FiveTuple_cp_query_en;
  wire FiveTuple_cp_query_del = r_FiveTuple_cp_query_del;
  wire FiveTuple_hit_out;
  wire [12:0] PacketCounter_cp_query_idx = r_PacketCounter_cp_query_idx;
  wire PacketCounter_cp_query_en  = r_PacketCounter_cp_query_en;
  wire [12:0] ByteCounter_cp_query_idx = r_ByteCounter_cp_query_idx;
  wire ByteCounter_cp_query_en  = r_ByteCounter_cp_query_en;
  wire PacketCounter_incr_en;
  wire [12:0] PacketCounter_incr_idx;
  wire ByteCounter_incr_en;
  wire [12:0] ByteCounter_incr_idx;

  processing_generated u_proc (
    .clk       (clk),
    .rst_n     (rst_n),
    .valid_in  (iss_fire),
    .eth_valid     (w_eth_valid),
    .vlan_valid     (w_vlan_valid),
    .ipv4_valid     (w_ipv4_valid),
    .ipv4opt_valid     (w_ipv4opt_valid),
    .tcp_valid     (w_tcp_valid),
    .tcpopt_valid     (w_tcpopt_valid),
    .udp_valid     (w_udp_valid),
    .new_vlan_valid     (w_new_vlan_valid),
    .eth_dmac  (w_eth_dmac),
    .eth_smac  (w_eth_smac),
    .eth_type  (w_eth_type),
    .vlan_pcp  (w_vlan_pcp),
    .vlan_cfi  (w_vlan_cfi),
    .vlan_vid  (w_vlan_vid),
    .vlan_tpid  (w_vlan_tpid),
    .ipv4_version  (w_ipv4_version),
    .ipv4_hdr_len  (w_ipv4_hdr_len),
    .ipv4_tos  (w_ipv4_tos),
    .ipv4_length  (w_ipv4_length),
    .ipv4_id  (w_ipv4_id),
    .ipv4_flags  (w_ipv4_flags),
    .ipv4_offset  (w_ipv4_offset),
    .ipv4_ttl  (w_ipv4_ttl),
    .ipv4_protocol  (w_ipv4_protocol),
    .ipv4_hdr_chk  (w_ipv4_hdr_chk),
    .ipv4_src  (w_ipv4_src),
    .ipv4_dst  (w_ipv4_dst),
    .ipv4opt_options  (w_ipv4opt_options),
    .tcp_src_port  (w_tcp_src_port),
    .tcp_dst_port  (w_tcp_dst_port),
    .tcp_seqNum  (w_tcp_seqNum),
    .tcp_ackNum  (w_tcp_ackNum),
    .tcp_dataOffset  (w_tcp_dataOffset),
    .tcp_resv  (w_tcp_resv),
    .tcp_flags  (w_tcp_flags),
    .tcp_window  (w_tcp_window),
    .tcp_checksum  (w_tcp_checksum),
    .tcp_urgPtr  (w_tcp_urgPtr),
    .tcpopt_options  (w_tcpopt_options),
    .udp_src_port  (w_udp_src_port),
    .udp_dst_port  (w_udp_dst_port),
    .udp_length  (w_udp_length),
    .udp_checksum  (w_udp_checksum),
    .new_vlan_pcp  (w_new_vlan_pcp),
    .new_vlan_cfi  (w_new_vlan_cfi),
    .new_vlan_vid  (w_new_vlan_vid),
    .new_vlan_tpid  (w_new_vlan_tpid),
    .out_eth_valid     (out_eth_valid),
    .out_vlan_valid     (out_vlan_valid),
    .out_ipv4_valid     (out_ipv4_valid),
    .out_ipv4opt_valid     (out_ipv4opt_valid),
    .out_tcp_valid     (out_tcp_valid),
    .out_tcpopt_valid     (out_tcpopt_valid),
    .out_udp_valid     (out_udp_valid),
    .out_new_vlan_valid     (out_new_vlan_valid),
    .out_eth_dmac  (out_eth_dmac),
    .out_eth_smac  (out_eth_smac),
    .out_eth_type  (out_eth_type),
    .out_vlan_pcp  (out_vlan_pcp),
    .out_vlan_cfi  (out_vlan_cfi),
    .out_vlan_vid  (out_vlan_vid),
    .out_vlan_tpid  (out_vlan_tpid),
    .out_ipv4_version  (out_ipv4_version),
    .out_ipv4_hdr_len  (out_ipv4_hdr_len),
    .out_ipv4_tos  (out_ipv4_tos),
    .out_ipv4_length  (out_ipv4_length),
    .out_ipv4_id  (out_ipv4_id),
    .out_ipv4_flags  (out_ipv4_flags),
    .out_ipv4_offset  (out_ipv4_offset),
    .out_ipv4_ttl  (out_ipv4_ttl),
    .out_ipv4_protocol  (out_ipv4_protocol),
    .out_ipv4_hdr_chk  (out_ipv4_hdr_chk),
    .out_ipv4_src  (out_ipv4_src),
    .out_ipv4_dst  (out_ipv4_dst),
    .out_ipv4opt_options  (out_ipv4opt_options),
    .out_tcp_src_port  (out_tcp_src_port),
    .out_tcp_dst_port  (out_tcp_dst_port),
    .out_tcp_seqNum  (out_tcp_seqNum),
    .out_tcp_ackNum  (out_tcp_ackNum),
    .out_tcp_dataOffset  (out_tcp_dataOffset),
    .out_tcp_resv  (out_tcp_resv),
    .out_tcp_flags  (out_tcp_flags),
    .out_tcp_window  (out_tcp_window),
    .out_tcp_checksum  (out_tcp_checksum),
    .out_tcp_urgPtr  (out_tcp_urgPtr),
    .out_tcpopt_options  (out_tcpopt_options),
    .out_udp_src_port  (out_udp_src_port),
    .out_udp_dst_port  (out_udp_dst_port),
    .out_udp_length  (out_udp_length),
    .out_udp_checksum  (out_udp_checksum),
    .out_new_vlan_pcp  (out_new_vlan_pcp),
    .out_new_vlan_cfi  (out_new_vlan_cfi),
    .out_new_vlan_vid  (out_new_vlan_vid),
    .out_new_vlan_tpid  (out_new_vlan_tpid),
    .FiveTuple_cp_wr_en  (FiveTuple_cp_wr_en),
    .FiveTuple_cp_wr_idx (FiveTuple_cp_wr_idx),
    .FiveTuple_cp_wr_action (FiveTuple_cp_wr_action),
    .FiveTuple_cp_wr_key_src (FiveTuple_cp_wr_key_src),
    .FiveTuple_cp_wr_key_dst (FiveTuple_cp_wr_key_dst),
    .FiveTuple_cp_wr_key_protocol (FiveTuple_cp_wr_key_protocol),
    .FiveTuple_cp_wr_key_table_key_sport (FiveTuple_cp_wr_key_table_key_sport),
    .FiveTuple_cp_wr_key_table_key_dport (FiveTuple_cp_wr_key_table_key_dport),
    .FiveTuple_cp_wr_p_counter_index (FiveTuple_cp_wr_p_counter_index),
    .FiveTuple_cp_wr_p_pcp (FiveTuple_cp_wr_p_pcp),
    .FiveTuple_cp_wr_p_cfi (FiveTuple_cp_wr_p_cfi),
    .FiveTuple_cp_wr_p_vid (FiveTuple_cp_wr_p_vid),
    .FiveTuple_cp_query_key_src (FiveTuple_cp_query_key_src),
    .FiveTuple_cp_query_key_dst (FiveTuple_cp_query_key_dst),
    .FiveTuple_cp_query_key_protocol (FiveTuple_cp_query_key_protocol),
    .FiveTuple_cp_query_key_table_key_sport (FiveTuple_cp_query_key_table_key_sport),
    .FiveTuple_cp_query_key_table_key_dport (FiveTuple_cp_query_key_table_key_dport),
    .FiveTuple_cp_query_en  (FiveTuple_cp_query_en),
    .FiveTuple_cp_query_del (FiveTuple_cp_query_del),
    .FiveTuple_cp_query_busy (FiveTuple_cp_query_busy),
    .FiveTuple_cp_query_hit  (FiveTuple_cp_query_hit),
    .FiveTuple_cp_query_action_id (FiveTuple_cp_query_action_id),
    .FiveTuple_cp_query_p_counter_index (FiveTuple_cp_query_p_counter_index),
    .FiveTuple_cp_query_p_pcp (FiveTuple_cp_query_p_pcp),
    .FiveTuple_cp_query_p_cfi (FiveTuple_cp_query_p_cfi),
    .FiveTuple_cp_query_p_vid (FiveTuple_cp_query_p_vid),
    .FiveTuple_hit_out  (FiveTuple_hit_out),
    .PacketCounter_incr_en  (PacketCounter_incr_en),
    .PacketCounter_incr_idx (PacketCounter_incr_idx),
    .ByteCounter_incr_en  (ByteCounter_incr_en),
    .ByteCounter_incr_idx (ByteCounter_incr_idx),
    .out_valid (proc_out_valid),   // aligned with out_*/drop
    .valid_out (proc_valid_out),   // legacy registered-late valid, unused here
    .drop      (proc_drop)
  );

  // ── Per-slot pipeline results ────────────────────────────────────────────
  // Captured on u_proc.out_valid (the data-ALIGNED valid) into slot cmp_slot.
  // The output PHV is stored, not an overlaid byte image, because at
  // completion the slot's later header rows may not have arrived yet
  // (cut-through): the overlay is done at TX time, when TX waits for them.
  logic slot_phv_eth_valid [0:NSLOT-1];
  logic slot_phv_vlan_valid [0:NSLOT-1];
  logic slot_phv_ipv4_valid [0:NSLOT-1];
  logic slot_phv_ipv4opt_valid [0:NSLOT-1];
  logic slot_phv_tcp_valid [0:NSLOT-1];
  logic slot_phv_tcpopt_valid [0:NSLOT-1];
  logic slot_phv_udp_valid [0:NSLOT-1];
  logic slot_phv_new_vlan_valid [0:NSLOT-1];
  logic [47:0] slot_phv_eth_dmac [0:NSLOT-1];
  logic [47:0] slot_phv_eth_smac [0:NSLOT-1];
  logic [15:0] slot_phv_eth_type [0:NSLOT-1];
  logic [2:0] slot_phv_vlan_pcp [0:NSLOT-1];
  logic [0:0] slot_phv_vlan_cfi [0:NSLOT-1];
  logic [11:0] slot_phv_vlan_vid [0:NSLOT-1];
  logic [15:0] slot_phv_vlan_tpid [0:NSLOT-1];
  logic [3:0] slot_phv_ipv4_version [0:NSLOT-1];
  logic [3:0] slot_phv_ipv4_hdr_len [0:NSLOT-1];
  logic [7:0] slot_phv_ipv4_tos [0:NSLOT-1];
  logic [15:0] slot_phv_ipv4_length [0:NSLOT-1];
  logic [15:0] slot_phv_ipv4_id [0:NSLOT-1];
  logic [2:0] slot_phv_ipv4_flags [0:NSLOT-1];
  logic [12:0] slot_phv_ipv4_offset [0:NSLOT-1];
  logic [7:0] slot_phv_ipv4_ttl [0:NSLOT-1];
  logic [7:0] slot_phv_ipv4_protocol [0:NSLOT-1];
  logic [15:0] slot_phv_ipv4_hdr_chk [0:NSLOT-1];
  logic [31:0] slot_phv_ipv4_src [0:NSLOT-1];
  logic [31:0] slot_phv_ipv4_dst [0:NSLOT-1];
  logic [319:0] slot_phv_ipv4opt_options [0:NSLOT-1];
  logic [15:0] slot_phv_tcp_src_port [0:NSLOT-1];
  logic [15:0] slot_phv_tcp_dst_port [0:NSLOT-1];
  logic [31:0] slot_phv_tcp_seqNum [0:NSLOT-1];
  logic [31:0] slot_phv_tcp_ackNum [0:NSLOT-1];
  logic [3:0] slot_phv_tcp_dataOffset [0:NSLOT-1];
  logic [5:0] slot_phv_tcp_resv [0:NSLOT-1];
  logic [5:0] slot_phv_tcp_flags [0:NSLOT-1];
  logic [15:0] slot_phv_tcp_window [0:NSLOT-1];
  logic [15:0] slot_phv_tcp_checksum [0:NSLOT-1];
  logic [15:0] slot_phv_tcp_urgPtr [0:NSLOT-1];
  logic [319:0] slot_phv_tcpopt_options [0:NSLOT-1];
  logic [15:0] slot_phv_udp_src_port [0:NSLOT-1];
  logic [15:0] slot_phv_udp_dst_port [0:NSLOT-1];
  logic [15:0] slot_phv_udp_length [0:NSLOT-1];
  logic [15:0] slot_phv_udp_checksum [0:NSLOT-1];
  logic [2:0] slot_phv_new_vlan_pcp [0:NSLOT-1];
  logic [0:0] slot_phv_new_vlan_cfi [0:NSLOT-1];
  logic [11:0] slot_phv_new_vlan_vid [0:NSLOT-1];
  logic [15:0] slot_phv_new_vlan_tpid [0:NSLOT-1];
  logic slot_cnt_PacketCounter_en [0:NSLOT-1];
  logic [12:0] slot_cnt_PacketCounter_idx [0:NSLOT-1];
  logic slot_cnt_ByteCounter_en [0:NSLOT-1];
  logic [12:0] slot_cnt_ByteCounter_idx [0:NSLOT-1];

  // ── RX (ingest) ──────────────────────────────────────────────────────────
  // Accept whenever the next slot is free and the payload FIFO has room.
  // Never because the pipeline or TX is busy -- that is the whole point.
  assign s_axis_tready = rx_slot_free && !pfifo_full;
  wire accept_beat = s_axis_tvalid && s_axis_tready;
  wire [8:0] rx_beat_cnt = slot_beat_cnt[wr_slot];
  wire accept_payload_beat = accept_beat && (rx_beat_cnt >= HDR_MAX_BEATS) && (rx_beat_cnt < MAX_PKT_BEATS);
  assign pfifo_wr_en   = accept_payload_beat;
  assign pfifo_wr_data = { (s_axis_tlast || (rx_beat_cnt == MAX_PKT_BEATS - 1)),
                            s_axis_tkeep, s_axis_tdata };

  logic rx_active;   // a packet is being received into wr_slot
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rel_ptr <= '0;
      rx_active <= 1'b0;
      for (int sl = 0; sl < NSLOT; sl++) begin
        slot_beat_cnt[sl] <= '0; slot_done[sl] <= 1'b0; slot_overflow[sl] <= 1'b0;
        slot_txdone[sl] <= 1'b0;
        slot_byte_len[sl] <= '0;
      end
    end else begin
      if (accept_beat) begin
        slot_byte_len[wr_slot] <= slot_byte_len[wr_slot] + ({15'd0, s_axis_tkeep[0]} + {15'd0, s_axis_tkeep[1]} + {15'd0, s_axis_tkeep[2]} + {15'd0, s_axis_tkeep[3]} + {15'd0, s_axis_tkeep[4]} + {15'd0, s_axis_tkeep[5]} + {15'd0, s_axis_tkeep[6]} + {15'd0, s_axis_tkeep[7]} + {15'd0, s_axis_tkeep[8]} + {15'd0, s_axis_tkeep[9]} + {15'd0, s_axis_tkeep[10]} + {15'd0, s_axis_tkeep[11]} + {15'd0, s_axis_tkeep[12]} + {15'd0, s_axis_tkeep[13]} + {15'd0, s_axis_tkeep[14]} + {15'd0, s_axis_tkeep[15]} + {15'd0, s_axis_tkeep[16]} + {15'd0, s_axis_tkeep[17]} + {15'd0, s_axis_tkeep[18]} + {15'd0, s_axis_tkeep[19]} + {15'd0, s_axis_tkeep[20]} + {15'd0, s_axis_tkeep[21]} + {15'd0, s_axis_tkeep[22]} + {15'd0, s_axis_tkeep[23]} + {15'd0, s_axis_tkeep[24]} + {15'd0, s_axis_tkeep[25]} + {15'd0, s_axis_tkeep[26]} + {15'd0, s_axis_tkeep[27]} + {15'd0, s_axis_tkeep[28]} + {15'd0, s_axis_tkeep[29]} + {15'd0, s_axis_tkeep[30]} + {15'd0, s_axis_tkeep[31]});
        if (rx_beat_cnt < HDR_MAX_BEATS) begin
          for (int i = 0; i < 32; i++)
            if (s_axis_tkeep[i])
              slot_hdr[wr_slot*HDR_MAX_BYTES + rx_beat_cnt*32 + i] <= s_axis_tdata[i*8 +: 8];
          slot_keep[wr_slot*HDR_MAX_BEATS + rx_beat_cnt] <= s_axis_tkeep;
          slot_beat_cnt[wr_slot] <= rx_beat_cnt + 9'd1;
        end else if (rx_beat_cnt < MAX_PKT_BEATS) begin
          slot_beat_cnt[wr_slot] <= rx_beat_cnt + 9'd1;
        end else begin
          slot_overflow[wr_slot] <= 1'b1;   // truncated; FIFO entry already marked last
        end
        rx_active <= !s_axis_tlast;
        if (s_axis_tlast) begin
          slot_done[wr_slot] <= 1'b1;
          wr_ptr <= wr_ptr + 1'b1;
        end
      end
      // slot release: TX has moved past rel_slot AND its tlast has arrived
      // TX finished with a slot: mark it, so release (which happens in
      // arrival order) can tell which slots are done under reordering.
      if (tx_finish) slot_txdone[tx_slot] <= 1'b1;
      if (slot_release) begin
        rel_ptr <= rel_ptr + 1'b1;
        slot_txdone[rel_slot] <= 1'b0;
        slot_beat_cnt[rel_slot] <= '0; slot_done[rel_slot] <= 1'b0; slot_overflow[rel_slot] <= 1'b0;
        slot_byte_len[rel_slot] <= '0;
      end
    end
  end

  // ── Issue (one-cycle valid_in pulse per packet) ──────────────────────────
  // Slot iss_slot is issuable once it is allocated (RX has at least started
  // it) and its header region has arrived -- the same cutoff the old shell
  // armed on. u_proc is a free-running pipeline: it captures the w_* inputs
  // on the issue edge, so nothing has to be held afterwards and the next
  // slot can be issued on the very next cycle.
  // iss_ptr can legitimately be ONE ahead of wr_ptr (a packet issued cut-
  // through before its tlast). "Behind" therefore has to exclude that case,
  // or an empty future slot would look allocated.
  wire iss_behind_wr = (iss_ptr != wr_ptr) && (iss_ptr != wr_ptr + 1'b1);
  // "RX is mid-packet in wr_slot" is tracked EXPLICITLY (rx_active), not
  // inferred from slot_beat_cnt != 0: wr_ptr advances on tlast even when the
  // next slot still holds an older packet awaiting TX, and that packet's
  // beat count is nonzero too -- inferring from it re-issued a stale slot.
  wire iss_allocated = iss_behind_wr || ((iss_ptr == wr_ptr) && rx_active);
  wire iss_hdr_ready = (slot_beat_cnt[iss_slot] * BEAT_BYTES >= cutoff_byte) || slot_done[iss_slot];
  assign iss_fire = iss_allocated && iss_hdr_ready;
  always_ff @(posedge clk) begin
    if (!rst_n) iss_ptr <= '0;
    else if (iss_fire) begin
      iss_ptr <= iss_ptr + 1'b1;
    end
  end

  // ── Enqueue (ingress done) and capture (egress done) ─────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cmp_ptr <= '0;
    end else begin
      if (proc_out_valid) begin
        cmp_ptr <= cmp_ptr + 1'b1;
        slot_drop[cmp_slot] <= proc_drop;
        slot_phv_eth_valid[cmp_slot] <= out_eth_valid;
        slot_phv_vlan_valid[cmp_slot] <= out_vlan_valid;
        slot_phv_ipv4_valid[cmp_slot] <= out_ipv4_valid;
        slot_phv_ipv4opt_valid[cmp_slot] <= out_ipv4opt_valid;
        slot_phv_tcp_valid[cmp_slot] <= out_tcp_valid;
        slot_phv_tcpopt_valid[cmp_slot] <= out_tcpopt_valid;
        slot_phv_udp_valid[cmp_slot] <= out_udp_valid;
        slot_phv_new_vlan_valid[cmp_slot] <= out_new_vlan_valid;
        slot_phv_eth_dmac[cmp_slot] <= out_eth_dmac;
        slot_phv_eth_smac[cmp_slot] <= out_eth_smac;
        slot_phv_eth_type[cmp_slot] <= out_eth_type;
        slot_phv_vlan_pcp[cmp_slot] <= out_vlan_pcp;
        slot_phv_vlan_cfi[cmp_slot] <= out_vlan_cfi;
        slot_phv_vlan_vid[cmp_slot] <= out_vlan_vid;
        slot_phv_vlan_tpid[cmp_slot] <= out_vlan_tpid;
        slot_phv_ipv4_version[cmp_slot] <= out_ipv4_version;
        slot_phv_ipv4_hdr_len[cmp_slot] <= out_ipv4_hdr_len;
        slot_phv_ipv4_tos[cmp_slot] <= out_ipv4_tos;
        slot_phv_ipv4_length[cmp_slot] <= out_ipv4_length;
        slot_phv_ipv4_id[cmp_slot] <= out_ipv4_id;
        slot_phv_ipv4_flags[cmp_slot] <= out_ipv4_flags;
        slot_phv_ipv4_offset[cmp_slot] <= out_ipv4_offset;
        slot_phv_ipv4_ttl[cmp_slot] <= out_ipv4_ttl;
        slot_phv_ipv4_protocol[cmp_slot] <= out_ipv4_protocol;
        slot_phv_ipv4_hdr_chk[cmp_slot] <= out_ipv4_hdr_chk;
        slot_phv_ipv4_src[cmp_slot] <= out_ipv4_src;
        slot_phv_ipv4_dst[cmp_slot] <= out_ipv4_dst;
        slot_phv_ipv4opt_options[cmp_slot] <= out_ipv4opt_options;
        slot_phv_tcp_src_port[cmp_slot] <= out_tcp_src_port;
        slot_phv_tcp_dst_port[cmp_slot] <= out_tcp_dst_port;
        slot_phv_tcp_seqNum[cmp_slot] <= out_tcp_seqNum;
        slot_phv_tcp_ackNum[cmp_slot] <= out_tcp_ackNum;
        slot_phv_tcp_dataOffset[cmp_slot] <= out_tcp_dataOffset;
        slot_phv_tcp_resv[cmp_slot] <= out_tcp_resv;
        slot_phv_tcp_flags[cmp_slot] <= out_tcp_flags;
        slot_phv_tcp_window[cmp_slot] <= out_tcp_window;
        slot_phv_tcp_checksum[cmp_slot] <= out_tcp_checksum;
        slot_phv_tcp_urgPtr[cmp_slot] <= out_tcp_urgPtr;
        slot_phv_tcpopt_options[cmp_slot] <= out_tcpopt_options;
        slot_phv_udp_src_port[cmp_slot] <= out_udp_src_port;
        slot_phv_udp_dst_port[cmp_slot] <= out_udp_dst_port;
        slot_phv_udp_length[cmp_slot] <= out_udp_length;
        slot_phv_udp_checksum[cmp_slot] <= out_udp_checksum;
        slot_phv_new_vlan_pcp[cmp_slot] <= out_new_vlan_pcp;
        slot_phv_new_vlan_cfi[cmp_slot] <= out_new_vlan_cfi;
        slot_phv_new_vlan_vid[cmp_slot] <= out_new_vlan_vid;
        slot_phv_new_vlan_tpid[cmp_slot] <= out_new_vlan_tpid;
        slot_cnt_PacketCounter_en[cmp_slot]  <= PacketCounter_incr_en;
        slot_cnt_PacketCounter_idx[cmp_slot] <= PacketCounter_incr_idx;
        slot_cnt_ByteCounter_en[cmp_slot]  <= ByteCounter_incr_en;
        slot_cnt_ByteCounter_idx[cmp_slot] <= ByteCounter_incr_idx;
      end
    end
  end

  // ── Transmit queue (no egress stage: completion is issue order) ─────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      txq_wr <= '0; txq_rd <= '0;
    end else begin
      if (proc_out_valid) begin
        txq_mem[txq_wr[SLOT_AW-1:0]] <= cmp_slot;
        txq_wr <= txq_wr + 1'b1;
      end
      if (tx_finish) txq_rd <= txq_rd + 1'b1;
    end
  end

  // ── TX-side view of slot tx_slot ─────────────────────────────────────────
  logic [7:0] t_hdr [0:HDR_MAX_BYTES-1];
  always_comb for (int i = 0; i < HDR_MAX_BYTES; i++) t_hdr[i] = slot_hdr[tx_slot*HDR_MAX_BYTES + i];
  wire phv_eth_valid = slot_phv_eth_valid[tx_slot];
  wire phv_vlan_valid = slot_phv_vlan_valid[tx_slot];
  wire phv_ipv4_valid = slot_phv_ipv4_valid[tx_slot];
  wire phv_ipv4opt_valid = slot_phv_ipv4opt_valid[tx_slot];
  wire phv_tcp_valid = slot_phv_tcp_valid[tx_slot];
  wire phv_tcpopt_valid = slot_phv_tcpopt_valid[tx_slot];
  wire phv_udp_valid = slot_phv_udp_valid[tx_slot];
  wire phv_new_vlan_valid = slot_phv_new_vlan_valid[tx_slot];
  wire [47:0] phv_eth_dmac = slot_phv_eth_dmac[tx_slot];
  wire [47:0] phv_eth_smac = slot_phv_eth_smac[tx_slot];
  wire [15:0] phv_eth_type = slot_phv_eth_type[tx_slot];
  wire [2:0] phv_vlan_pcp = slot_phv_vlan_pcp[tx_slot];
  wire [0:0] phv_vlan_cfi = slot_phv_vlan_cfi[tx_slot];
  wire [11:0] phv_vlan_vid = slot_phv_vlan_vid[tx_slot];
  wire [15:0] phv_vlan_tpid = slot_phv_vlan_tpid[tx_slot];
  wire [3:0] phv_ipv4_version = slot_phv_ipv4_version[tx_slot];
  wire [3:0] phv_ipv4_hdr_len = slot_phv_ipv4_hdr_len[tx_slot];
  wire [7:0] phv_ipv4_tos = slot_phv_ipv4_tos[tx_slot];
  wire [15:0] phv_ipv4_length = slot_phv_ipv4_length[tx_slot];
  wire [15:0] phv_ipv4_id = slot_phv_ipv4_id[tx_slot];
  wire [2:0] phv_ipv4_flags = slot_phv_ipv4_flags[tx_slot];
  wire [12:0] phv_ipv4_offset = slot_phv_ipv4_offset[tx_slot];
  wire [7:0] phv_ipv4_ttl = slot_phv_ipv4_ttl[tx_slot];
  wire [7:0] phv_ipv4_protocol = slot_phv_ipv4_protocol[tx_slot];
  wire [15:0] phv_ipv4_hdr_chk = slot_phv_ipv4_hdr_chk[tx_slot];
  wire [31:0] phv_ipv4_src = slot_phv_ipv4_src[tx_slot];
  wire [31:0] phv_ipv4_dst = slot_phv_ipv4_dst[tx_slot];
  wire [319:0] phv_ipv4opt_options = slot_phv_ipv4opt_options[tx_slot];
  wire [15:0] phv_tcp_src_port = slot_phv_tcp_src_port[tx_slot];
  wire [15:0] phv_tcp_dst_port = slot_phv_tcp_dst_port[tx_slot];
  wire [31:0] phv_tcp_seqNum = slot_phv_tcp_seqNum[tx_slot];
  wire [31:0] phv_tcp_ackNum = slot_phv_tcp_ackNum[tx_slot];
  wire [3:0] phv_tcp_dataOffset = slot_phv_tcp_dataOffset[tx_slot];
  wire [5:0] phv_tcp_resv = slot_phv_tcp_resv[tx_slot];
  wire [5:0] phv_tcp_flags = slot_phv_tcp_flags[tx_slot];
  wire [15:0] phv_tcp_window = slot_phv_tcp_window[tx_slot];
  wire [15:0] phv_tcp_checksum = slot_phv_tcp_checksum[tx_slot];
  wire [15:0] phv_tcp_urgPtr = slot_phv_tcp_urgPtr[tx_slot];
  wire [319:0] phv_tcpopt_options = slot_phv_tcpopt_options[tx_slot];
  wire [15:0] phv_udp_src_port = slot_phv_udp_src_port[tx_slot];
  wire [15:0] phv_udp_dst_port = slot_phv_udp_dst_port[tx_slot];
  wire [15:0] phv_udp_length = slot_phv_udp_length[tx_slot];
  wire [15:0] phv_udp_checksum = slot_phv_udp_checksum[tx_slot];
  wire [2:0] phv_new_vlan_pcp = slot_phv_new_vlan_pcp[tx_slot];
  wire [0:0] phv_new_vlan_cfi = slot_phv_new_vlan_cfi[tx_slot];
  wire [11:0] phv_new_vlan_vid = slot_phv_new_vlan_vid[tx_slot];
  wire [15:0] phv_new_vlan_tpid = slot_phv_new_vlan_tpid[tx_slot];

  // header byte offsets over the stored PHV (same arithmetic as w_*_base)
  wire [13:0] phv_ipv4_base = 14 + ((phv_eth_type == 16'h8100) ? 4 : 0);
  wire [13:0] phv_ipv4_hdr_bytes = {10'b0, phv_ipv4_hdr_len} << 2;
  wire [13:0] phv_ipv4opt_base = phv_ipv4_base + phv_ipv4_hdr_bytes;
  wire [13:0] phv_tcp_base = phv_ipv4_base + phv_ipv4_hdr_bytes;
  wire [13:0] phv_tcpopt_base = phv_ipv4_base + phv_ipv4_hdr_bytes;
  wire [13:0] phv_udp_base = phv_ipv4_base + phv_ipv4_hdr_bytes;

  // ── Deparser: header-region assembly for slot tx_slot ────────────────────
  // Received bytes of the slot with its stored output PHV overlaid at each
  // header's layout offset, guarded by the stored output validity.
  logic [7:0] hdr_out [0:HDR_MAX_BYTES-1];
  always_comb begin
    for (int i = 0; i < HDR_MAX_BYTES; i++) hdr_out[i] = t_hdr[i];
    hdr_out[0] = phv_eth_dmac[47:40];
    hdr_out[1] = phv_eth_dmac[39:32];
    hdr_out[2] = phv_eth_dmac[31:24];
    hdr_out[3] = phv_eth_dmac[23:16];
    hdr_out[4] = phv_eth_dmac[15:8];
    hdr_out[5] = phv_eth_dmac[7:0];
    hdr_out[6] = phv_eth_smac[47:40];
    hdr_out[7] = phv_eth_smac[39:32];
    hdr_out[8] = phv_eth_smac[31:24];
    hdr_out[9] = phv_eth_smac[23:16];
    hdr_out[10] = phv_eth_smac[15:8];
    hdr_out[11] = phv_eth_smac[7:0];
    hdr_out[12] = phv_eth_type[15:8];
    hdr_out[13] = phv_eth_type[7:0];
    if (phv_vlan_valid) begin
        hdr_out[14] = {phv_vlan_pcp, phv_vlan_cfi, phv_vlan_vid[11:8]};
        hdr_out[14+1] = phv_vlan_vid[7:0];
        hdr_out[14+2] = phv_vlan_tpid[15:8];
        hdr_out[14+3] = phv_vlan_tpid[7:0];
    end
    if (phv_ipv4_valid) begin
        hdr_out[phv_ipv4_base] = {phv_ipv4_version, phv_ipv4_hdr_len};
        hdr_out[phv_ipv4_base+1] = phv_ipv4_tos;
        hdr_out[phv_ipv4_base+2] = phv_ipv4_length[15:8];
        hdr_out[phv_ipv4_base+3] = phv_ipv4_length[7:0];
        hdr_out[phv_ipv4_base+4] = phv_ipv4_id[15:8];
        hdr_out[phv_ipv4_base+5] = phv_ipv4_id[7:0];
        hdr_out[phv_ipv4_base+6] = {phv_ipv4_flags, phv_ipv4_offset[12:8]};
        hdr_out[phv_ipv4_base+7] = phv_ipv4_offset[7:0];
        hdr_out[phv_ipv4_base+8] = phv_ipv4_ttl;
        hdr_out[phv_ipv4_base+9] = phv_ipv4_protocol;
        hdr_out[phv_ipv4_base+10] = phv_ipv4_hdr_chk[15:8];
        hdr_out[phv_ipv4_base+11] = phv_ipv4_hdr_chk[7:0];
        hdr_out[phv_ipv4_base+12] = phv_ipv4_src[31:24];
        hdr_out[phv_ipv4_base+13] = phv_ipv4_src[23:16];
        hdr_out[phv_ipv4_base+14] = phv_ipv4_src[15:8];
        hdr_out[phv_ipv4_base+15] = phv_ipv4_src[7:0];
        hdr_out[phv_ipv4_base+16] = phv_ipv4_dst[31:24];
        hdr_out[phv_ipv4_base+17] = phv_ipv4_dst[23:16];
        hdr_out[phv_ipv4_base+18] = phv_ipv4_dst[15:8];
        hdr_out[phv_ipv4_base+19] = phv_ipv4_dst[7:0];
    end
    if (phv_ipv4opt_valid) begin
        hdr_out[phv_ipv4opt_base] = phv_ipv4opt_options[319:312];
        hdr_out[phv_ipv4opt_base+1] = phv_ipv4opt_options[311:304];
        hdr_out[phv_ipv4opt_base+2] = phv_ipv4opt_options[303:296];
        hdr_out[phv_ipv4opt_base+3] = phv_ipv4opt_options[295:288];
        hdr_out[phv_ipv4opt_base+4] = phv_ipv4opt_options[287:280];
        hdr_out[phv_ipv4opt_base+5] = phv_ipv4opt_options[279:272];
        hdr_out[phv_ipv4opt_base+6] = phv_ipv4opt_options[271:264];
        hdr_out[phv_ipv4opt_base+7] = phv_ipv4opt_options[263:256];
        hdr_out[phv_ipv4opt_base+8] = phv_ipv4opt_options[255:248];
        hdr_out[phv_ipv4opt_base+9] = phv_ipv4opt_options[247:240];
        hdr_out[phv_ipv4opt_base+10] = phv_ipv4opt_options[239:232];
        hdr_out[phv_ipv4opt_base+11] = phv_ipv4opt_options[231:224];
        hdr_out[phv_ipv4opt_base+12] = phv_ipv4opt_options[223:216];
        hdr_out[phv_ipv4opt_base+13] = phv_ipv4opt_options[215:208];
        hdr_out[phv_ipv4opt_base+14] = phv_ipv4opt_options[207:200];
        hdr_out[phv_ipv4opt_base+15] = phv_ipv4opt_options[199:192];
        hdr_out[phv_ipv4opt_base+16] = phv_ipv4opt_options[191:184];
        hdr_out[phv_ipv4opt_base+17] = phv_ipv4opt_options[183:176];
        hdr_out[phv_ipv4opt_base+18] = phv_ipv4opt_options[175:168];
        hdr_out[phv_ipv4opt_base+19] = phv_ipv4opt_options[167:160];
        hdr_out[phv_ipv4opt_base+20] = phv_ipv4opt_options[159:152];
        hdr_out[phv_ipv4opt_base+21] = phv_ipv4opt_options[151:144];
        hdr_out[phv_ipv4opt_base+22] = phv_ipv4opt_options[143:136];
        hdr_out[phv_ipv4opt_base+23] = phv_ipv4opt_options[135:128];
        hdr_out[phv_ipv4opt_base+24] = phv_ipv4opt_options[127:120];
        hdr_out[phv_ipv4opt_base+25] = phv_ipv4opt_options[119:112];
        hdr_out[phv_ipv4opt_base+26] = phv_ipv4opt_options[111:104];
        hdr_out[phv_ipv4opt_base+27] = phv_ipv4opt_options[103:96];
        hdr_out[phv_ipv4opt_base+28] = phv_ipv4opt_options[95:88];
        hdr_out[phv_ipv4opt_base+29] = phv_ipv4opt_options[87:80];
        hdr_out[phv_ipv4opt_base+30] = phv_ipv4opt_options[79:72];
        hdr_out[phv_ipv4opt_base+31] = phv_ipv4opt_options[71:64];
        hdr_out[phv_ipv4opt_base+32] = phv_ipv4opt_options[63:56];
        hdr_out[phv_ipv4opt_base+33] = phv_ipv4opt_options[55:48];
        hdr_out[phv_ipv4opt_base+34] = phv_ipv4opt_options[47:40];
        hdr_out[phv_ipv4opt_base+35] = phv_ipv4opt_options[39:32];
        hdr_out[phv_ipv4opt_base+36] = phv_ipv4opt_options[31:24];
        hdr_out[phv_ipv4opt_base+37] = phv_ipv4opt_options[23:16];
        hdr_out[phv_ipv4opt_base+38] = phv_ipv4opt_options[15:8];
        hdr_out[phv_ipv4opt_base+39] = phv_ipv4opt_options[7:0];
    end
    if (phv_tcp_valid) begin
        hdr_out[phv_tcp_base] = phv_tcp_src_port[15:8];
        hdr_out[phv_tcp_base+1] = phv_tcp_src_port[7:0];
        hdr_out[phv_tcp_base+2] = phv_tcp_dst_port[15:8];
        hdr_out[phv_tcp_base+3] = phv_tcp_dst_port[7:0];
        hdr_out[phv_tcp_base+4] = phv_tcp_seqNum[31:24];
        hdr_out[phv_tcp_base+5] = phv_tcp_seqNum[23:16];
        hdr_out[phv_tcp_base+6] = phv_tcp_seqNum[15:8];
        hdr_out[phv_tcp_base+7] = phv_tcp_seqNum[7:0];
        hdr_out[phv_tcp_base+8] = phv_tcp_ackNum[31:24];
        hdr_out[phv_tcp_base+9] = phv_tcp_ackNum[23:16];
        hdr_out[phv_tcp_base+10] = phv_tcp_ackNum[15:8];
        hdr_out[phv_tcp_base+11] = phv_tcp_ackNum[7:0];
        hdr_out[phv_tcp_base+12] = {phv_tcp_dataOffset, phv_tcp_resv[5:2]};
        hdr_out[phv_tcp_base+13] = {phv_tcp_resv[1:0], phv_tcp_flags};
        hdr_out[phv_tcp_base+14] = phv_tcp_window[15:8];
        hdr_out[phv_tcp_base+15] = phv_tcp_window[7:0];
        hdr_out[phv_tcp_base+16] = phv_tcp_checksum[15:8];
        hdr_out[phv_tcp_base+17] = phv_tcp_checksum[7:0];
        hdr_out[phv_tcp_base+18] = phv_tcp_urgPtr[15:8];
        hdr_out[phv_tcp_base+19] = phv_tcp_urgPtr[7:0];
    end
    if (phv_tcpopt_valid) begin
        hdr_out[phv_tcpopt_base] = phv_tcpopt_options[319:312];
        hdr_out[phv_tcpopt_base+1] = phv_tcpopt_options[311:304];
        hdr_out[phv_tcpopt_base+2] = phv_tcpopt_options[303:296];
        hdr_out[phv_tcpopt_base+3] = phv_tcpopt_options[295:288];
        hdr_out[phv_tcpopt_base+4] = phv_tcpopt_options[287:280];
        hdr_out[phv_tcpopt_base+5] = phv_tcpopt_options[279:272];
        hdr_out[phv_tcpopt_base+6] = phv_tcpopt_options[271:264];
        hdr_out[phv_tcpopt_base+7] = phv_tcpopt_options[263:256];
        hdr_out[phv_tcpopt_base+8] = phv_tcpopt_options[255:248];
        hdr_out[phv_tcpopt_base+9] = phv_tcpopt_options[247:240];
        hdr_out[phv_tcpopt_base+10] = phv_tcpopt_options[239:232];
        hdr_out[phv_tcpopt_base+11] = phv_tcpopt_options[231:224];
        hdr_out[phv_tcpopt_base+12] = phv_tcpopt_options[223:216];
        hdr_out[phv_tcpopt_base+13] = phv_tcpopt_options[215:208];
        hdr_out[phv_tcpopt_base+14] = phv_tcpopt_options[207:200];
        hdr_out[phv_tcpopt_base+15] = phv_tcpopt_options[199:192];
        hdr_out[phv_tcpopt_base+16] = phv_tcpopt_options[191:184];
        hdr_out[phv_tcpopt_base+17] = phv_tcpopt_options[183:176];
        hdr_out[phv_tcpopt_base+18] = phv_tcpopt_options[175:168];
        hdr_out[phv_tcpopt_base+19] = phv_tcpopt_options[167:160];
        hdr_out[phv_tcpopt_base+20] = phv_tcpopt_options[159:152];
        hdr_out[phv_tcpopt_base+21] = phv_tcpopt_options[151:144];
        hdr_out[phv_tcpopt_base+22] = phv_tcpopt_options[143:136];
        hdr_out[phv_tcpopt_base+23] = phv_tcpopt_options[135:128];
        hdr_out[phv_tcpopt_base+24] = phv_tcpopt_options[127:120];
        hdr_out[phv_tcpopt_base+25] = phv_tcpopt_options[119:112];
        hdr_out[phv_tcpopt_base+26] = phv_tcpopt_options[111:104];
        hdr_out[phv_tcpopt_base+27] = phv_tcpopt_options[103:96];
        hdr_out[phv_tcpopt_base+28] = phv_tcpopt_options[95:88];
        hdr_out[phv_tcpopt_base+29] = phv_tcpopt_options[87:80];
        hdr_out[phv_tcpopt_base+30] = phv_tcpopt_options[79:72];
        hdr_out[phv_tcpopt_base+31] = phv_tcpopt_options[71:64];
        hdr_out[phv_tcpopt_base+32] = phv_tcpopt_options[63:56];
        hdr_out[phv_tcpopt_base+33] = phv_tcpopt_options[55:48];
        hdr_out[phv_tcpopt_base+34] = phv_tcpopt_options[47:40];
        hdr_out[phv_tcpopt_base+35] = phv_tcpopt_options[39:32];
        hdr_out[phv_tcpopt_base+36] = phv_tcpopt_options[31:24];
        hdr_out[phv_tcpopt_base+37] = phv_tcpopt_options[23:16];
        hdr_out[phv_tcpopt_base+38] = phv_tcpopt_options[15:8];
        hdr_out[phv_tcpopt_base+39] = phv_tcpopt_options[7:0];
    end
    if (phv_udp_valid) begin
        hdr_out[phv_udp_base] = phv_udp_src_port[15:8];
        hdr_out[phv_udp_base+1] = phv_udp_src_port[7:0];
        hdr_out[phv_udp_base+2] = phv_udp_dst_port[15:8];
        hdr_out[phv_udp_base+3] = phv_udp_dst_port[7:0];
        hdr_out[phv_udp_base+4] = phv_udp_length[15:8];
        hdr_out[phv_udp_base+5] = phv_udp_length[7:0];
        hdr_out[phv_udp_base+6] = phv_udp_checksum[15:8];
        hdr_out[phv_udp_base+7] = phv_udp_checksum[7:0];
    end
  end

  // ── TX (egress) ──────────────────────────────────────────────────────────
  // No start cycle and no finish-on-consume: the slot at tx_slot is "live"
  // the moment its result is captured (cmp_ptr != tx_ptr), its first row
  // loads on any cycle the output register is free, and the packet is
  // FINISHED when its last beat is LOADED into tx_out (the data is a copy,
  // so the slot can be released right then). tx_ptr advances on that
  // edge, so on the cycle the last beat is consumed the next slot's first
  // row is already loading -- one beat per cycle across packet boundaries.
  // Before this TX cost ~2.5 cycles per packet on top of its beats (a
  // start cycle plus finish-on-consume), which was the whole gap to ideal.
  // Per-slot facts (drop, metadata, counter request) are read straight
  // from the slot each cycle -- they are stable for the slot's lifetime --
  // so nothing needs latching at a start event. The metadata sideband
  // rides in tx_out with the beat, so it changes exactly when the first
  // beat of the next packet is presented.
  wire tx_consumed  = tx_out_valid && m_axis_tready;
  wire tx_slot_free = !tx_out_valid || tx_consumed;
  wire slot_live    = (txq_wr != txq_rd);
  wire cur_discard  = slot_drop[tx_slot];
  wire [8:0] tx_beat_cnt_s = slot_beat_cnt[tx_slot];
  wire tx_done_s        = slot_done[tx_slot];
  wire pkt_ends_in_hdr  = tx_done_s && (tx_beat_cnt_s <= HDR_MAX_BEATS);
  wire hdr_row_ready    = (tx_hdr_row < tx_beat_cnt_s) && (tx_hdr_row < HDR_MAX_BEATS);
  wire hdr_row_is_last  = tx_done_s && (tx_hdr_row == tx_beat_cnt_s - 9'd1);
  wire emit_hdr    = slot_live && !cur_discard && !tx_in_payload && hdr_row_ready && tx_slot_free;
  wire emit_pl     = slot_live && !cur_discard &&  tx_in_payload && pfifo_rd_valid && tx_slot_free;
  wire discard_pop = slot_live &&  cur_discard && pfifo_rd_valid;
  assign pfifo_rd_en = emit_pl || discard_pop;
  wire last_loaded  = (emit_hdr && hdr_row_is_last) || (emit_pl && pfifo_head_last);
  wire discard_done = slot_live && cur_discard && (pkt_ends_in_hdr || (discard_pop && pfifo_head_last));
  assign tx_finish  = last_loaded || discard_done;
  wire slot_release = slot_done[rel_slot] && slot_txdone[rel_slot];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tx_in_payload <= 1'b0;
      tx_hdr_row    <= '0;
      tx_out_valid  <= 1'b0;
      tx_out_data   <= '0;
      tx_out_keep   <= '0;
      tx_out_last   <= 1'b0;
    end else begin
      if (tx_consumed) tx_out_valid <= 1'b0;
      if (emit_hdr) begin
        tx_out_valid <= 1'b1;
        for (int i = 0; i < 32; i++)
          tx_out_data[i*8 +: 8] <= hdr_out[tx_hdr_row * 32 + i];
        tx_out_keep  <= slot_keep[tx_slot*HDR_MAX_BEATS + tx_hdr_row];
        tx_out_last  <= hdr_row_is_last;
        tx_hdr_row   <= tx_hdr_row + 9'd1;
        if (!hdr_row_is_last && tx_hdr_row == HDR_MAX_BEATS - 1) tx_in_payload <= 1'b1;
      end else if (emit_pl) begin
        tx_out_valid <= 1'b1;
        tx_out_data  <= pfifo_head_data;
        tx_out_keep  <= pfifo_head_keep;
        tx_out_last  <= pfifo_head_last;
      end
      if (tx_finish) begin
        tx_in_payload <= 1'b0;
        tx_hdr_row    <= '0;
      end
    end
  end

  PacketCounter_counter #(.DEPTH(8192)) u_PacketCounter (
    .clk (clk), .rst_n (rst_n),
    .incr_fire (slot_release),
    .incr_req  (slot_cnt_PacketCounter_en[rel_slot]),
    .incr_idx  (slot_cnt_PacketCounter_idx[rel_slot]),
    .cp_query_en  (PacketCounter_cp_query_en),
    .cp_query_idx (PacketCounter_cp_query_idx),
    .cp_query_busy (PacketCounter_cp_query_busy),
    .cp_query_pkt_value (PacketCounter_cp_query_pkt_value)
  );

  ByteCounter_counter #(.DEPTH(8192)) u_ByteCounter (
    .clk (clk), .rst_n (rst_n),
    .incr_fire (slot_release),
    .incr_req  (slot_cnt_ByteCounter_en[rel_slot]),
    .incr_idx  (slot_cnt_ByteCounter_idx[rel_slot]),
    .pkt_byte_len (slot_byte_len[rel_slot]),
    .cp_query_en  (ByteCounter_cp_query_en),
    .cp_query_idx (ByteCounter_cp_query_idx),
    .cp_query_busy (ByteCounter_cp_query_busy),
    .cp_query_byte_value (ByteCounter_cp_query_byte_value)
  );

  // ── TX output ────────────────────────────────────────────────────────────
  // Plain registered pass-through -- see the always_ff above for the fetch/
  // issue logic that fills tx_out_*. tlast is additionally gated on tx_out_valid
  // defensively (tx_out_last could otherwise hold a stale value across a clear).
  assign m_axis_tvalid = tx_out_valid;
  assign m_axis_tdata  = tx_out_data;
  assign m_axis_tkeep  = tx_out_keep;
  assign m_axis_tlast  = tx_out_valid && tx_out_last;

endmodule
