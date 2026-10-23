"""Build the compiler's IR for an app, without emitting any RTL.

Reuses main.py's own front-end call and ingester, so the model is reading
exactly what the emitters read -- not a second parse that could drift.
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.normpath(os.path.join(_HERE, '..', '..'))
sys.path.insert(0, os.path.join(_ROOT, 'compiler'))

import main as compiler_main        # noqa: E402
from ingest_p4ir import ingest_p4ir  # noqa: E402


def app_path(app):
    return os.path.join(_ROOT, 'p4src', 'apps', f'{app}.p4')


def build_ir(app, p4test_bin=None):
    """The IR for p4src/apps/<app>.p4 (p4test front end only).

    The bmv2 front end is deliberately not offered: those programs have no
    top-level byte stream, so there is nothing for a pcap to drive.
    """
    path = app_path(app)
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    arch = compiler_main._detect_p4_arch(path)
    if arch not in ('p4rtl', 'xsa'):
        raise ValueError(
            f'{app}: architecture {arch!r} has no top-level packet interface; '
            f'this framework drives <app>_top.sv over AXI4-Stream')
    # The front end prints its own progress and p4test's warnings. Captured,
    # not shown: the framework's verdict is what the caller came for, and the
    # compiler's own run already reported those warnings.
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        text = compiler_main._run_p4c_frontend(path, p4test_bin)
    return ingest_p4ir(text)
