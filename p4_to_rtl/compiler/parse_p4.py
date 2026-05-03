import re


def parse_p4_file(filepath):
    with open(filepath, "r") as f:
        lines = f.readlines()

    parser_states = []
    current_state = None

    in_parser = False
    in_select = False

    select_expr = None
    select_cases = []
    select_default = None

    for line in lines:
        line = line.strip()

        # -------------------------------
        # Enter parser
        # -------------------------------
        if re.match(r"parser\s+\w+", line):
            in_parser = True
            continue

        if not in_parser:
            continue

        # -------------------------------
        # State start
        # -------------------------------
        state_match = re.match(r"state\s+(\w+)", line)
        if state_match:
            current_state = {
                "name": state_match.group(1),
                "extract": None,
                "transition": None,
                "select": None
            }
            continue

        # -------------------------------
        # Extract
        # -------------------------------
        extract_match = re.search(r"extract\s*\(\s*hdr\.(\w+)\s*\)", line)
        if extract_match and current_state:
            current_state["extract"] = extract_match.group(1)
            continue

        # -------------------------------
        # transition select(...)
        # -------------------------------
        if line.startswith("transition select") and current_state:
            in_select = True

            select_expr = re.search(r"select\s*\((.*?)\)", line).group(1)

            select_cases = []
            select_default = None
            continue

        # -------------------------------
        # Inside select block
        # -------------------------------
        if in_select:
            case_match = re.match(r"(.*?)\s*:\s*(\w+)\s*;", line)

            if case_match:
                key = case_match.group(1).strip()
                val = case_match.group(2).strip()

                if key in ["default", "_"]:
                    select_default = val
                else:
                    select_cases.append((key, val))
                continue

            # end select
            if line == "}":
                current_state["select"] = {
                    "expr": select_expr,
                    "cases": select_cases,
                    "default": select_default
                }
                in_select = False
                continue

        # -------------------------------
        # Simple transition
        # -------------------------------
        if line.startswith("transition") and current_state and not in_select:

            if "select" in line:
                continue

            transition = line.replace("transition", "").strip(" ;")
            current_state["transition"] = transition
            continue

        # -------------------------------
        # End state
        # -------------------------------
        if line == "}" and current_state and not in_select:
            parser_states.append(current_state)
            current_state = None
            continue

        # -------------------------------
        # Exit parser
        # -------------------------------
        if line == "}" and not current_state:
            in_parser = False

    return {
        "parser": {
            "states": parser_states
        }
    }