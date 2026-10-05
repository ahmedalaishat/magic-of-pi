# Computes 1,000,000 decimals of e, √2 and φ with exact integer arithmetic.
#   python3 tools/compute_constants.py <output folder>   (writes e.txt, sqrt2.txt, phi.txt; ~1 minute)
# Pack each with tools/pack_digits.py into PiVisualizer/<name>-digits.bin.
import sys, math, time
sys.set_int_max_str_digits(0)
N = 1_000_000          # decimals kept
G = 30                 # guard digits
one = 10 ** (N + G)
t = time.time()
# e = Σ 1/k!, as exact integer arithmetic scaled by 10^(N+G).
e, term, k = 0, one, 0
while term:
    e += term
    k += 1
    term //= k
print("e", round(time.time() - t, 1), flush=True)
sqrt2 = math.isqrt(2 * one * one)
phi = (math.isqrt(5 * one * one) + one) // 2
out = sys.argv[1]
for name, value, prefix in [("e", e, "2718281828459045235360"), ("sqrt2", sqrt2, "1414213562373095048801"),
                            ("phi", phi, "1618033988749894848204")]:
    s = str(value)[: N + 1]
    assert s.startswith(prefix), name
    open(f"{out}/{name}.txt", "w").write(s)
    print(name, len(s), s[:15], s[-10:], flush=True)
print("done", round(time.time() - t, 1))
