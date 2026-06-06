"""
Handles OP-1 Field MIDI port detection and connection.

Returns a single shared mido.open_input() port used by both clock.py and
controller.py.  The OP-1 exposes one combined MIDI in/out port; we open
input for receiving clock and output for sending CC.
"""

import mido


OP1_KEYWORD = "op-1"  # matched case-insensitively against port names


def list_ports() -> tuple[list[str], list[str]]:
    """Return (input_ports, output_ports)."""
    return mido.get_input_names(), mido.get_output_names()


def _find_op1(names: list[str]) -> str | None:
    for name in names:
        if OP1_KEYWORD in name.lower():
            return name
    return None


def _prompt_user(names: list[str], direction: str) -> str:
    print(f"\nAvailable MIDI {direction} ports:")
    for i, name in enumerate(names):
        print(f"  [{i}] {name}")
    while True:
        raw = input(f"Select {direction} port number: ").strip()
        if raw.isdigit() and 0 <= int(raw) < len(names):
            return names[int(raw)]
        print("Invalid selection, try again.")


def connect() -> tuple[mido.ports.BaseInput, mido.ports.BaseOutput]:
    """
    Detect the OP-1 Field and open input+output ports.

    Returns (in_port, out_port).  If auto-detection fails the user is
    prompted to choose manually.
    """
    in_names, out_names = list_ports()

    print("Available MIDI input ports:")
    for name in in_names:
        print(f"  • {name}")
    print("Available MIDI output ports:")
    for name in out_names:
        print(f"  • {name}")

    in_name = _find_op1(in_names)
    if in_name:
        print(f"\nAuto-detected OP-1 input:  {in_name}")
    else:
        print("\nOP-1 not found by name — manual selection required.")
        in_name = _prompt_user(in_names, "input")

    out_name = _find_op1(out_names)
    if out_name:
        print(f"Auto-detected OP-1 output: {out_name}")
    else:
        out_name = _prompt_user(out_names, "output")

    in_port = mido.open_input(in_name)
    out_port = mido.open_output(out_name)
    return in_port, out_port
