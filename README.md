# P4_Compiler_Design P4-to-RTL Compiler

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

## Quick Start

```bash
# Compile an application
cd compiler
python main.py qos
python main.py firewall --frontend bmv2
