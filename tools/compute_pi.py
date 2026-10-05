# Computes digits of π with the Chudnovsky series and binary splitting (exact integer arithmetic).
#   python3 tools/compute_pi.py pi.txt            (10,000,000 decimals by default; ~8 minutes)
# Output: "3" followed by the decimals, digits only. Pack it with tools/pack_digits.py.
# A guard of extra digits is computed and dropped, so the last kept digits are exact.
# 1,000,000 digits of π by the Chudnovsky series with binary splitting (exact integers).
import sys, time, math
sys.set_int_max_str_digits(0)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 10_000_000
t0 = time.time()
C3_24 = 640320**3 // 24
def bs(a, b):
    if b - a == 1:
        if a == 0:
            P = Q = 1
        else:
            P = (6*a - 5) * (2*a - 1) * (6*a - 1)
            Q = a*a*a * C3_24
        T = P * (13591409 + 545140134*a)
        if a & 1: T = -T
        return P, Q, T
    m = (a + b) // 2
    P1, Q1, T1 = bs(a, m); P2, Q2, T2 = bs(m, b)
    return P1*P2, Q1*Q2, Q2*T1 + P1*T2
terms = int((N + 120) / 14.18) + 2
P, Q, T = bs(0, terms)
print("series", round(time.time() - t0, 1), flush=True)
one = 10**(N + 120)
sqrt_c = math.isqrt(10005 * one * one)
print("sqrt", round(time.time() - t0, 1), flush=True)
pi = (Q * 426880 * sqrt_c) // T
print("divide", round(time.time() - t0, 1), flush=True)
s = str(pi)[:N + 1]
print("str", round(time.time() - t0, 1), len(s), s[:12], s[-12:], flush=True)
open(sys.argv[1], "w").write(s)
