from math import trunc

# Precompute a small lookup table for the reciprocal initial guess in [1, 2)
# The table stores approximations to 1/x for representative points across [1, 2)
_RECIP_LUT = [1.0 / (1.0 + (i + 0.5) / 16.0) for i in range(16)]

def _initial_guess_from_lut(denominator: int) -> float:
    if denominator <= 0:
        raise ValueError("Denominator must be positive")
    # Normalize denominator to x * 2^k with x in [1, 2)
    bitlen = denominator.bit_length()
    k = bitlen - 1
    x = denominator / (1 << k)
    # Map x in [1, 2) to an index in the LUT
    idx = int((x - 1.0) * 16.0)
    if idx < 0:
        idx = 0
    elif idx >= len(_RECIP_LUT):
        idx = len(_RECIP_LUT) - 1
    # 1/D = (1/x) * 2^-k
    return _RECIP_LUT[idx] / (1 << k)

def div_nr(N, D, G=None):
    if G is None:
        G = _initial_guess_from_lut(D)
    change = 1
    G_prev = G
    G_new = G
    iter = 0

    while change > G/100000:
        G_new = G * (2-D*G)
        # print(f"Iteration {iter}: G = {G_new}")
        change = abs(G_new - G_prev)
        G_prev = G_new
        G = G_new
        iter += 1
    
    print(G)

    Q = trunc(N * G)
    R = N - D * Q

    if R >= D:
        Q += 1
        R -= D

    return Q, R

print(div_nr(24, 6))