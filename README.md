# P4-to-RTL Compiler

Translate P4 programs into synthesizable SystemVerilog RTL for FPGA/ASIC.

## Overview

An open-source, vendor-agnostic compiler that generates a complete hardware pipeline (Parser → Match-Action → Deparser) from a P4 description. Outputs are pure SystemVerilog with AXI4-Stream and AXI4-Lite interfaces, ready for synthesis on any platform.

## Key Features

- **Multi-Frontend Support**: Ingests BMv2 JSON (`p4c`) or MidEnd P4 IR (`p4test`).
- **Optimized Table Backends**:
  - Exact-match: XOR-fold hash → 1-cycle BRAM lookup.
  - LPM/Ternary: Balanced binary tree with registered leaf comps (1-cycle).
  - Keyless: Control-plane-writable default-action register.
- **Full Ingress & Egress** pipeline compilation.
- **Pure SystemVerilog** output – no proprietary IP or toolchain lock-in.
- **Explicit Pipeline Scheduling** with metadata hazard detection.
- **Target Board Abstraction**: Vendor-neutral synthesis pragmas (Xilinx/Altera) with constraint-file skeletons.
- **On-Chip Self-Test Wrapper**: Optional packet generator + capture for hardware validation without an Ethernet MAC/PHY.
- **Timing-Driven Pipeline Splitting**: Optional budget-based stage partitioning for high-frequency closure.

## Quick Start

```bash
# Compile an application (auto-detects frontend from P4 source)
cd compiler
python main.py qos

# Force specific frontend
python main.py firewall --frontend bmv2
python main.py fiveTuple --frontend p4test

# Generate for a specific board (affects synthesis pragmas + emits constraint skeleton)
python main.py qos --board de2-115 --axi-data-width 256

# Include on-chip self-test wrapper for hardware validation
python main.py fiveTuple --self-test --board zybo

# Target a specific frequency (enables timing-driven pipeline splitting)
python main.py qos --target-freq-mhz 400 --device artix7

# Use d-way set-associative exact-match tables
python main.py firewall --exact-match-ways 4
```

## Architecture

The compiler translates a P4 program into a hardware pipeline through several distinct stages:

### Frontend Selection

The compiler automatically detects the target architecture from the P4 source:

- `XilinxPipeline` → uses `p4test` MidEnd IR frontend (produces a complete top-level design with AXI4-Stream and AXI4-Lite interfaces)
- `V1Switch` → uses `p4c-bm2-ss` BMv2 JSON frontend (produces just the processing core; no top-level wrapper)

You can override auto-detection with `--frontend bmv2` or `--frontend p4test`.

### Hardware IR Generation

Both frontends produce a unified hardware IR (`ir.py`) that abstracts away frontend-specific details:

- **Parser States**: Extract headers from the incoming packet byte stream
- **Header Types**: Field widths and layouts
- **Tables**: Match-action tables with keys, actions, and default entries
- **Control Flow**: `if`/`else` statements, `table.apply()` calls, action invocations
- **Deparser Order**: Ordered list of headers to emit

### RTL Code Generation

The compiler emits synthesizable SystemVerilog for each pipeline stage:

| Module | Description |
|---|---|
| `parser_generated.sv` | Parser FSM with field extraction |
| `{table}_table.sv` | One module per match-action table |
| `processing_generated.sv` | Match-action pipeline with table lookups and actions |
| `egress_processing_generated.sv` | Egress processing (if present) |
| `deparser_generated.sv` | Header emission in deparser order |
| `{app}_top.sv` | `p4test` only: AXI4-Stream + AXI4-Lite wrapper |
| `{app}_selftest_top.sv` | Optional: On-chip generator + capture wrapper |
| `{app}.xdc` / `{app}.qsf` + `{app}.sdc` | Board-specific: Constraint-file skeletons |

## Target Board Abstraction

The compiler supports vendor-neutral RTL generation through a board descriptor system (`boards.py`). Board descriptors are JSON files in `compiler/boards/` that define toolchain-specific synthesis pragmas and constraint formats.

### Supported Boards

| Board | Vendor | Toolchain | Device Part |
|---|---|---|---|
| Terasic DE2-115 | Altera | Quartus | EP4CE115F29C7 |
| Digilent Zybo | Xilinx | Vivado | Zynq-7000 (board revision-dependent) |

### Board-Specific Behavior

When `--board <name>` is specified:

- **RAM Style Pragma**: Uses the board's preferred RAM inference attribute (`ram_style = "block"` for Vivado, `ramstyle = "M9K"` for Quartus)
- **FSM Encoding Pragma**: Uses the board's preferred state-machine encoding (`fsm_encoding = "one_hot"` for Vivado; Quartus has no reliable inline equivalent, so a comment is emitted instead)
- **Constraint-File Skeleton**: Generates a structural constraint file with TODO placeholders for pin/ball assignments:
  - Xilinx: `.xdc` (clock creation + I/O constraints)
  - Altera: `.qsf` (family, device, top-level entity, SDC file) + `.sdc` (clock creation)

> **Important**: Pin/ball locations are not fabricated by the compiler. You must copy them from your board's official master constraint file before synthesis.

### Adding a New Board

1. Create `compiler/boards/<name>.json` with the required keys (see `boards.py` for schema)
2. The compiler will automatically discover it when `--board` is used

## On-Chip Self-Test Wrapper

The `--self-test` flag generates `{app}_selftest_top.sv`, a standalone wrapper around `{app}_top.sv` that includes:

- **Writable Template Buffer**: Software constructs packet bytes via a dedicated AXI4-Lite bus
- **Packet Generator**: Streams the template buffer N times with optional byte sweeping
- **Packet Capture**: Captures the DUT's output for read-back verification
- **Independent Control Bus**: Separate AXI4-Lite slave from the table control plane

### Resource Impact

- Adds 2x `MAX_PKT_BYTES` of on-chip packet buffering (template + capture)
- Total packet memory roughly triples when using this feature
- At default 256-bit width: 8KB → 24KB
- At maximum 512-bit width: 16KB → 48KB

### Register Map

See `emit_selftest.py` for the full register map (word-addressed, AXI4-Lite bus). Key registers:

| Offset | Register | Description |
|---|---|---|
| `0x00` | `gen_pkt_len` | Bytes to send per packet |
| `0x04` | `gen_pkt_count` | Packets in burst |
| `0x08` | `gen_vary_offset` | Template byte offset that auto-increments |
| `0x0C` | `gen_vary_enable` | Enable byte sweeping (bit 0) |
| `0x10` | `gen_ipg` | Inter-packet gap (clock cycles) |
| `0x14` | `gen_start` | Write strobe to start generation |
| `0x18` | `gen_status` | Read: busy (bit 0), done (bit 1) |
| `0x1C` | `gen_sent_count` | Packets completed this burst |
| `0x20` | `cap_start` | Write strobe to arm capture |
| `0x24` | `cap_status` | Read: armed/busy (bit 0), done/valid (bit 1) |
| `0x28` | `cap_byte_count` | Bytes captured for the last packet |
| `0x2C` | `max_pkt_bytes` | Read-only: maximum packet size (capability discovery) |

### Usage Notes

- `cap_start` must be written before `gen_start` (cut-through datapath can start output before input finishes)
- The self-test wrapper is only meaningful for the `p4test`/XSA frontend
- Getting a real bus master (e.g., Vivado JTAG-to-AXI-Master) onto the board is a separate integration step

## Timing-Driven Pipeline Splitting

The `--target-freq-mhz` flag enables an optional pipeline optimization that splits combinational logic across multiple registers to meet a timing budget.

### How It Works

1. **Real Calibration**: The timing model is anchored to a single real measurement:
   - Artix-7 `xc7a100tcsg324-1` at 93 MHz: 16 logic levels on the worst path
   - This measurement comes from a real `synth_design` + `report_timing` run
2. **Cost Estimation**: Each expression is assigned a logic-level cost based on:
   - Arithmetic: `CARRY_LEVELS_PER_8B = 2` (measured from the calibration point)
   - Comparisons: ~log2(width) levels (balanced tree of LUT6s)
   - MUXes: ~1 level per 2:1 select
   - Unknown constructs: charged a conservative penalty (better to over-estimate)
3. **Device Scaling**: The model scales the budget using device-specific factors:
   - `artix7`: 1.0 (the only measured entry)
   - `ultrascale-plus`: 0.6 (public-doc estimate, unverified)
   - `versal`: 0.45 (public-doc estimate, unverified)
4. **Stage Splitting**:
   - Exact-match tables: Optional split between tag-compare and action-select
   - LPM/Ternary tables: Balanced priority tree split across multiple registers
   - Apply-block statements: Flattened statement lists split at budget boundaries

### Important Caveats

- UltraScale+/Versal timing estimates are **unverified** on this machine (no Synthesis license for these device classes)
- The model is deliberately conservative: over-estimating costs adds extra registers (harmless), while under-estimating would produce false "meets budget" claims
- Any unrecognized construct prints a `[WARN]` and is charged a large penalty

## Set-Associative Exact-Match Tables

The `--exact-match-ways N` flag enables d-way set-associative storage for exact-match tables.

### Behavior

- Default (`ways=1`): Direct-mapped hash table (a write to an occupied bucket silently overwrites)
- `ways > 1`: CP writes only become genuine collisions once all `ways` slots at a bucket hold different keys

### Outputs

For d-way associative tables, the following additional ports are exposed:

| Port | Description |
|---|---|
| `{table}_wr_collision` | High when a write targets a full bucket with no matching key |
| `{table}_cp_wr_busy` | High while a CP write is in progress (2-cycle write latency) |

### Notes

- Lookup latency is unchanged (same as direct-mapped)
- CP writes are staged over 2 cycles (allocate read + commit)
- LPM/Ternary/Keyless tables ignore this flag

## Control-Plane Query/Delete (p4test only)

For plain (`ways=1`) exact-match tables, the compiler exposes a control-plane query/delete port:

| Port | Description |
|---|---|
| `{table}_cp_query_en` | Strobe to initiate a query |
| `{table}_cp_query_del` | If high, delete the entry on hit |
| `{table}_cp_query_key_*` | Key fields to look up |
| `{table}_cp_query_busy` | High while query is in progress |
| `{table}_cp_query_hit` | High if the key was found |
| `{table}_cp_query_action_id` | Action ID of the matched entry |
| `{table}_cp_query_p_*` | Parameters of the matched entry |

> **Important**: This feature is only available for the `p4test`/XSA frontend (the BMv2 frontend has no bus wrapper to drive these ports).

## Command-Line Reference

```text
python main.py <app> [options]
```

### Positional Arguments

| Argument | Description |
|---|---|
| `app` | P4 application name (without `.p4` extension) |

### Frontend Options

| Option | Description |
|---|---|
| `--p4c PATH` | Path to `p4c-bm2-ss` binary (v1model frontend) |
| `--p4test PATH` | Path to `p4test` binary (XSA/MidEnd frontend) |
| `--frontend {p4test,bmv2}` | Force a specific frontend (auto-detect by default) |

### Synthesis Options

| Option | Description |
|---|---|
| `--target-freq-mhz FLOAT` | Enable timing-driven pipeline splitting at target frequency |
| `--device {artix7,ultrascale-plus,versal}` | Target device family for frequency scaling (default: `artix7`) |
| `--exact-match-ways N` | d-way set-associative exact-match tables (default: 1) |
| `--axi-data-width BITS` | AXI4-Stream TDATA width (default: 256, max: 512) |

### Board Options

| Option | Description |
|---|---|
| `--board NAME` | Target board descriptor (affects pragmas + constraint skeletons) |
| `--self-test` | Generate on-chip generator + capture wrapper |

## File Structure

```text
compiler/
├── main.py              # Compiler driver
├── boards.py            # Board descriptor loader/validator
├── emit_*.py            # RTL code generators
├── ingest_*.py          # Frontend parsers
├── ir.py                # Hardware IR data structures
├── timing_model.py      # Delay-cost estimation
├── boards/              # Board descriptor JSON files
│   ├── de2-115.json
│   └── zybo.json
└── p4src/apps/          # P4 application sources
    ├── qos.p4
    ├── firewall.p4
    └── ...
```

## Output Directory

Generated RTL is placed in `generated/<app>/`:

```text
generated/<app>/
├── <app>_pkg.sv                    # Package with typedefs and constants
├── parser_generated.sv             # Parser FSM
├── processing_generated.sv         # Ingress match-action pipeline
├── egress_processing_generated.sv  # (if egress present)
├── deparser_generated.sv           # Deparser
├── <app>_top.sv                    # (p4test only) AXI wrapper
├── <app>_selftest_top.sv           # (--self-test) Generator + capture wrapper
├── <app>.xdc                       # (--board xilinx) XDC skeleton
├── <app>.qsf                       # (--board altera) QSF skeleton
├── <app>.sdc                       # (--board altera) SDC skeleton
└── */*_table.sv                    # One module per match-action table
```

## Requirements

- Python 3.8+
- P4 compiler (either `p4c` for BMv2 or `p4test` for XSA):
  - For BMv2: `p4c-bm2-ss` on `PATH`, or set `P4C` environment variable
  - For p4test: `p4test` from a p4c build, or set `P4TEST` environment variable
- Verilog/SystemVerilog simulator (for verification)
- FPGA synthesis toolchain (Vivado, Quartus, etc.) for hardware implementation
