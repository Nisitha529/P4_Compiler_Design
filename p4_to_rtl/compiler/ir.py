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


class HeaderInstance:
    """Maps a P4 header instance name (e.g. 'eth') to its type definition."""
    def __init__(self, inst_name, type_name, header_type, is_stack=False, stack_size=0):
        self.inst_name   = inst_name
        self.type_name   = type_name
        self.header_type = header_type   # ref to Header
        self.is_stack    = is_stack
        self.stack_size  = stack_size


class MetadataField:
    def __init__(self, name, width):
        self.name  = name
        self.width = width


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


class ActionParam:
    """A typed action parameter: name, P4 type string, resolved bit width."""
    def __init__(self, name, type_str, width=None):
        self.name     = name
        self.type_str = type_str
        self.width    = width   # None means unresolved


class Action:
    def __init__(self, name):
        self.name = name
        self.params = []        # list[ActionParam]
        self.body = []          # list[Assignment | ExternCall]

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

    def add_then(self, stmt):
        self.then_body.append(stmt)

    def add_else(self, stmt):
        self.else_body.append(stmt)


class TableApply(Statement):
    def __init__(self, table_name):
        self.table_name = table_name
        self.result_var = None


class ExternCall(Statement):
    def __init__(self, name, args):
        self.name = name
        self.args = args


class LocalVar:
    """A control-block-level variable: bit<N> name;"""
    def __init__(self, name, type_str, width):
        self.name     = name
        self.type_str = type_str
        self.width    = width


class RegisterDecl:
    """A register<bit<N>>(size) name; extern declaration."""
    def __init__(self, name, data_width, size):
        self.name       = name
        self.data_width = data_width
        self.size       = size


class ControlBlock:
    def __init__(self, name):
        self.name = name
        self.statements = []     # list[Statement]  (apply-block order)
        self.tables = []         # list[Table]       (local to this block)
        self.actions = []        # list[Action]      (local to this block)
        self.local_vars = []     # list[LocalVar]    (bit<N> x; declarations)
        self.registers  = []     # list[RegisterDecl]

    def add_statement(self, stmt):
        self.statements.append(stmt)

    def add_table(self, table):
        self.tables.append(table)

    def add_action(self, action):
        self.actions.append(action)

    def add_local_var(self, var):
        self.local_vars.append(var)

    def add_register(self, reg):
        self.registers.append(reg)


# ============================================================
# Deparser IR
# ============================================================

class Deparser:
    def __init__(self):
        self.emit_list = []      # list[str]  — ordered header names


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

        # Headers — type definitions
        self.headers = []
        self.header_stacks = []

        # Header instances (struct headers { ... }) — inst name -> type
        self.header_instances = []     # list[HeaderInstance]
        self.header_type_map  = {}     # type_name -> Header

        # Metadata fields (struct metadata { ... })
        self.metadata_fields = []      # list[MetadataField]

        # Tables / Actions  (flat, across all controls)
        self.tables = []
        self.actions = []

        # Control blocks  (keyed by name: ingress, egress, …)
        self.controls = {}

        # Type / constant info  (for emit_pkg.py)
        self.typedefs = {}
        self.consts = {}

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
        self.header_type_map[header.name] = header

    def add_header_stack(self, stack):
        self.header_stacks.append(stack)

    def add_header_instance(self, inst):
        self.header_instances.append(inst)

    def add_metadata_field(self, field):
        self.metadata_fields.append(field)

    # ---------------- Tables / Actions (flat) ----------------
    def add_table(self, table):
        self.tables.append(table)

    def add_action(self, action):
        self.actions.append(action)

    # ---------------- Control blocks ----------------
    def add_control(self, block):
        self.controls[block.name] = block

    def get_control(self, name):
        return self.controls.get(name)

    # ---------------- Type info ----------------
    def set_typedefs(self, td):
        self.typedefs = td

    def set_consts(self, c):
        self.consts = c

    # ---------------- Pipeline ----------------
    def set_pipeline_stage(self, stage, ref):
        setattr(self.pipeline, stage, ref)
