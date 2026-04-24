import re

def parse_p4_file(filepath):
    with open(filepath, "r") as f:
        lines = f.readlines()

    parser_states = []
    current_state = None

    in_parser_block = False

    for line in lines:
        line = line.strip()

        # Enter parser block
        if re.match(r"parser\s+\w+", line):
            in_parser_block = True
            continue

        if not in_parser_block:
            continue

        # Detect state definition
        # Example: state start {
        state_match = re.match(r"state\s+(\w+)", line)
        if state_match:
            current_state = {
                "name": state_match.group(1),
                "transition": None,
                "extract": None,
                "select": None
            }
            continue

        # Detect extract
        # Example: packet.extract(hdr.ethernet);
        extract_match = re.search(r"extract\s*\(\s*hdr\.(\w+)\s*\)", line)
        if extract_match and current_state is not None:
            current_state["extract"] = extract_match.group(1)
            continue

        # Detect transition
        # Example: transition accept;
        if line.startswith("transition") and current_state is not None:
            transition = line.split("transition")[1].strip(" ;")
            current_state["transition"] = transition
            continue

        # Detect select-based transition
        # Example:
        # transition select(hdr.ethernet.etherType)
        select_match = re.search(r"select\s*\(\s*(.*?)\s*\)", line)
        if select_match and current_state is not None:
            current_state["select"] = select_match.group(1)
            continue

        # End of state block
        if line == "}" and current_state is not None:
            # only append valid states
            if current_state["transition"] is not None:
                parser_states.append(current_state)

            current_state = None
            continue

        # Exit parser block
        if line.endswith("}"):
            in_parser_block = False

    return {
        "parser": {
            "states": parser_states
        }
    }