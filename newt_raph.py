from math import trunc

_RECIP_LUT = [1.0 / (1.0 + (i + 0.5) / 16.0) for i in range(16)]

def _initial_guess_from_lut(denominator: int) -> float:
    if denominator <= 0:
        raise ValueError("Denominator must be positive")
    bitlen = denominator.bit_length()
    k = bitlen - 1
    x = denominator / (1 << k)
    idx = int((x - 1.0) * 16.0)
    if idx < 0:
        idx = 0
    elif idx >= len(_RECIP_LUT):
        idx = len(_RECIP_LUT) - 1
    return _RECIP_LUT[idx] / (1 << k)

def div_nr(N, D, G=None, O='Q'):
    if G is None:
        G = _initial_guess_from_lut(D)
    change = 1
    G_prev = G
    G_new = G
    iter = 0

    while change > G/100000:
        G_new = G * (2-D*G)
        print(f"Iteration {iter}: G = {G_new}")
        change = abs(G_new - G_prev)
        G_prev = G_new
        G = G_new
        iter += 1

    Q = trunc(N * G)
    R = N - D * Q

    if R < 0:
        adjust = (-R + D - 1) // D
        Q -= adjust
        R += adjust * D
    elif R >= D:
        adjust = R // D
        Q += adjust
        R -= adjust * D

    if O == 'Q':
        return Q
    elif O == 'R':
        return R
    else:
        raise ValueError("Invalid output option")

print(div_nr(17, 5, None, 'R'))