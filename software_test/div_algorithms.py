from math import inf, trunc

# Precompute a small lookup table for the reciprocal initial guess in [1, 2)
# The table stores approximations to 1/x for representative points across [1, 2)
_RECIP_LUT = [1.0 / (1.0 + (i + 0.5) / 16.0) for i in range(16)]
print(_RECIP_LUT)

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

# print(div_nr(24, 6))


def div_gs(N, D):

    N_prev = N
    D_prev = D
    iter = 0
    num_shifts = 0

    while D > 1:
        D = D >> 1
        num_shifts += 1


    F = 2 - D

    N_new = inf
    D_new = inf

    while abs(N_new - N_prev) > N/100000:
        N_new = N_prev * F
        D_new = D_prev * F

        F = 2 - D_new
        N_prev = N_new
        D_prev = D_new
        iter += 1

    Q = N_new << num_shifts
    R = N_new - D_new * Q

    return Q, R