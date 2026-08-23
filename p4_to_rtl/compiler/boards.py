"""
Board descriptor loading/validation for the opt-in --board flag (main.py).

A board descriptor is a plain dict (loaded from compiler/boards/<name>.json)
describing enough about a target board's toolchain to make the compiler's two
hardcoded Xilinx/Vivado synthesis pragmas (emit_parser.py's fsm_encoding,
emit_top.py's ram_style) vendor-correct, and to select a constraint-file
skeleton format (emit_constraints.py). This is deliberately NOT a full board
bring-up description -- no PLL/clock-domain, MAC, or pin-assignment data.
"""
import json
import os

_BOARDS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'boards')

_REQUIRED_KEYS = {
    'name', 'display_name', 'vendor', 'toolchain', 'device_family',
    'constraint_format', 'ram_style_pragma', 'fsm_encoding_pragma',
    'device_part', 'device_part_verified', 'device_part_note', 'notes',
}
_SUPPORTED_VENDORS = {'xilinx', 'altera'}


def available_boards():
    """Sorted board names discoverable from compiler/boards/*.json."""
    if not os.path.isdir(_BOARDS_DIR):
        return []
    return sorted(fn[:-5] for fn in os.listdir(_BOARDS_DIR) if fn.endswith('.json'))


def validate_board(board):
    """
    Validate an in-memory board descriptor dict. Re-usable directly by
    emit_parser.py/emit_top.py/emit_constraints.py (not just load_board()),
    since those functions can be called programmatically with a hand-built
    dict, not only via the CLI -- same dual-validation precedent as
    emit_top.py's axi_data_width parameter.
    """
    if not isinstance(board, dict):
        raise ValueError(f'board must be a dict (or None) -- got {type(board).__name__}')
    missing = _REQUIRED_KEYS - board.keys()
    if missing:
        raise ValueError(f'board descriptor missing required keys: {sorted(missing)}')
    if board['vendor'] not in _SUPPORTED_VENDORS:
        raise ValueError(
            f"unsupported board vendor '{board['vendor']}' -- only "
            f"{sorted(_SUPPORTED_VENDORS)} have constraint-skeleton emitters implemented"
        )
    return board


def load_board(name):
    """Load and validate a board descriptor by name (compiler/boards/<name>.json)."""
    path = os.path.join(_BOARDS_DIR, f'{name}.json')
    if not os.path.exists(path):
        raise ValueError(
            f"Unknown board '{name}' -- no {path}. "
            f"Available boards: {', '.join(available_boards())}"
        )
    with open(path) as f:
        board = json.load(f)
    return validate_board(board)
