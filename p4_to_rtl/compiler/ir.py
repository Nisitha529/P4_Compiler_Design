class ParserState:
    def __init__(self, name, transition):
        self.name = name
        self.transition = transition


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


class Table:
    def __init__(self, name):
        self.name = name
        self.keys = []
        self.actions = []


class Action:
    def __init__(self, name):
        self.name = name
        self.params = []


class IR:
    def __init__(self):
        # Parser
        self.parser_states = []

        # Headers
        self.headers = []

        # Match-action
        self.tables = []
        self.actions = []

    # -------------------------
    # Helper methods
    # -------------------------
    def add_parser_state(self, name, transition):
        self.parser_states.append(ParserState(name, transition))

    def add_header(self, header):
        self.headers.append(header)

    def add_table(self, table):
        self.tables.append(table)

    def add_action(self, action):
        self.actions.append(action)