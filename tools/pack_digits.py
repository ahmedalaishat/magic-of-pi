# Packs a number's digits two per byte (high nibble first) for the app bundle.
#   python3 tools/pack_digits.py pi-digits.txt PiVisualizer/pi-digits.bin
# The input is the integer digit followed by the decimals, digits only (e.g. "31415…").
# An odd count is padded with a 0xF nibble.
import sys

digits = open(sys.argv[1]).read().strip()
assert digits.isdigit()
values = [int(c) for c in digits]
if len(values) % 2:
    values.append(0xF)
packed = bytes((values[i] << 4) | values[i + 1] for i in range(0, len(values), 2))
open(sys.argv[2], "wb").write(packed)
print(f"{len(digits):,} digits -> {len(packed):,} bytes")
