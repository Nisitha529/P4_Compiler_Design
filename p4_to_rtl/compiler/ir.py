# ============================================================
# Parser IR
# ============================================================

class Extract:
    def __init__(self, header, dynamic=False, length_expr=None):
        self.header = header
        self.dynamic = dynamic
        self.length_expr = length_expr


class Verify:
    def __init__(self, condition, error=None):
        self.condition = condition
        self.error = error


class ParserSelect:
    def __init__(self, expression):
        self.expression = expression
        self.cases = []            # [(value, next_state)]
        self.default = None

    def add_case(self, value, next_state):
        self.cases.append((value, next_state))

    def set_default(self, next_state):
        self.default = next_state


class ParserState:
    def __init__(self, name):
        self.name = name

        self.extracts = []         # list[Extract]
        self.verifies = []         # list[Verify]

        self.next_state = None     # direct transition
        self.select = None         # ParserSelect

    def add_extract(self, extract):
        self.extracts.append(extract)

    def add_verify(self, verify):
        self.verifies.append(verify)

    def set_transition(self, next_state):
        self.next_state = next_state

    def set_select(self, select):
        self.select = select


# ============================================================
# Header IR
# ============================================================

class HeaderField:
    def __init__(self, name, width):
        self.name = name
        self.width = width


class Header:
    def __init__(self, name):
        self.name = name
        self.fields = []

    def add_field(self, field):
        self.fields.append(field)


class HeaderStack:
    def __init__(self, name, size):
        self.name = name
        self.size = size


# ============================================================
# Table IR
# ============================================================

class TableKey:
    def __init__(self, field, match_type="exact"):
        self.field = field
        self.match_type = match_type   # exact / lpm / ternary


class Table:
    def __init__(self, name):
        self.name = name
        self.keys = []              # list[TableKey]
        self.actions = []           # list[str]
        self.default_action = None

    def add_key(self, key):
        self.keys.append(key)

    def add_action(self, action):
        self.actions.append(action)

    def set_default(self, action):
        self.default_action = action


# ============================================================
# Action IR
# ============================================================

class Assignment:
    def __init__(self, lhs, rhs):
        self.lhs = lhs
        self.rhs = rhs


class Action:
    def __init__(self, name):
        self.name = name
        self.params = []
        self.body = []   # list of statements

    def add_param(self, param):
        self.params.append(param)

    def add_statement(self, stmt):
        self.body.append(stmt)


# ============================================================
# Control Flow IR
# ============================================================

class Statement:
    pass


class IfStatement(Statement):
    def __init__(self, condition):
        self.condition = condition
        self.then_body = []
        self.else_body = []


class TableApply(Statement):
    def __init__(self, table_name):
        self.table_name = table_name
        self.result_var = None   # optional (hit/miss)


class ExternCall(Statement):
    def __init__(self, name, args):
        self.name = name
        self.args = args


class ControlBlock:
    def __init__(self, name):
        self.name = name
        self.statements = []


# ============================================================
# Deparser IR
# ============================================================

class Deparser:
    def __init__(self):
        self.emit_list = []


# ============================================================
# Pipeline IR
# ============================================================

class Pipeline:
    def __init__(self):
        self.parser = None
        self.verify = None
        self.ingress = None
        self.egress = None
        self.compute_checksum = None
        self.deparser = None


# ============================================================
# Top-level IR
# ============================================================

class IR:
    def __init__(self):

        # Parser
        self.parser_states = {}
        self.start_state = None

        # Headers
        self.headers = []
        self.header_stacks = []

        # Tables / Actions
        self.tables = []
        self.actions = []

        # Pipeline
        self.pipeline = Pipeline()

    # ---------------- Parser ----------------
    def add_parser_state(self, state):
        self.parser_states[state.name] = state

    def get_state(self, name):
        return self.parser_states.get(name)

    def set_start_state(self, name):
        self.start_state = name

    # ---------------- Headers ----------------
    def add_header(self, header):
        self.headers.append(header)

    def add_header_stack(self, stack):
        self.header_stacks.append(stack)

    # ---------------- Tables ----------------
    def add_table(self, table):
        self.tables.append(table)

    def add_action(self, action):
        self.actions.append(action)