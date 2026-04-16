import re


def parse_p4_file(filepath):
    with open(filepath, "r") as f:
        lines = f.readlines()

    parser_states = []
    current_state = None

    in_parser_block = False

    for line in lines:
        line = line.strip()

        # -----------------------------------------
        # Enter parser block
        # -----------------------------------------
        if line.startswith("parser"):
            in_parser_block = True
            continue

        if not in_parser_block:
            continue

        # -----------------------------------------
        # Detect state definition
        # Example: state start {
        # -----------------------------------------
        state_match = re.match(r"state\s+(\w+)", line)
        if state_match:
            current_state = {
                "name": state_match.group(1),
                "transition": None
            }
            continue

        # -----------------------------------------
        # Detect transition
        # Example: transition accept;
        # -----------------------------------------
        if line.startswith("transition") and current_state is not None:
            transition = line.split("transition")[1].strip(" ;")
            current_state["transition"] = transition
            continue

        # -----------------------------------------
        # End of state block
        # -----------------------------------------
        if line == "}" and current_state is not None:
            # only append valid states
            if current_state["transition"] is not None:
                parser_states.append(current_state)

            current_state = None
            continue

        # -----------------------------------------
        # Exit parser block
        # -----------------------------------------
        if line.endswith("}"):
            in_parser_block = False

    return {
        "parser": {
            "states": parser_states
        }
    }