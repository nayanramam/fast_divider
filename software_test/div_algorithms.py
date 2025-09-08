from math import trunc

from math import isfinite, trunc

def div_gs_v2(N: int, D: int, max_iters: int = 30):
    """
    Goldschmidt division (float prototype, unsigned).
    Returns (Q, R, iters) with Q = trunc(N/D), R = N - D*Q.
    """
    # Normalize so d0 in [0.5, 1).  For integer D, let s = bitlen - 1:
    # D in [2^s, 2^(s+1)-1]  => d0 = D / 2^(s+1) ∈ [0.5, 1)
    s = D.bit_length() - 1
    scale = 1 << (s + 1)
    n = N >> scale
    d = D >> scale

    # Initial factor. With d in [0.5,1), F0 = 2 - d is a decent first step.
    F = 2.0 - d

    iters = 0
    for iters in range(max_iters):
        n *= F
        d *= F
        F = 2.0 - d


    # Correct residue into [0, D)
    Q = trunc(n)
    R = N - D * Q

    if R >= D:
        Q += 1
        R -= D

    return Q, R, iters


def div_gs(N, D):

    iter = 0
    num_shifts = 0

    s = D.bit_length() - 1
    scale = 1 << (s + 1)
    N_prev = N >> scale
    D_prev = D >> scale


    F = 2 - D_prev

    N_new = float   ('inf')
    D_new =     float('inf')

    while abs(N_new - N_prev) > N/100000:
        N_new = N_prev * F
        D_new = D_prev * F

        F = 2 - D_new
        N_prev = N_new
        D_prev = D_new
        iter += 1

    Q = N_new << num_shifts
    R = N_new - D_new * Q

    return Q, R, iter





def div_gs_v1(N, D):

    N_prev = N
    D_prev = D
    iter = 0
    num_shifts = 0

    while D > 1:
        D = D >> 1
        num_shifts += 1


    F = 2 - D

    N_new = float('inf')
    D_new = float('inf')

    while abs(N_new - N_prev) > N/100000:
        N_new = N_prev * F
        D_new = D_prev * F

        F = 2 - D_new
        N_prev = N_new
        D_prev = D_new
        iter += 1

    Q = N_new << num_shifts
    R = N_new - D_new * Q

    return Q, R, iter

















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
        #print(f"Iteration {iter}: G = {G_new}")
        change = abs(G_new - G_prev)
        G_prev = G_new
        G = G_new
        iter += 1
    
    #print(f"Iteration {iter}: G = {G_new}")

    Q = trunc(N * G)
    R = N - D * Q

    if R >= D:
        Q += 1
        R -= D

    return Q, R, iter

#print(div_nr(24, 6))


LUT = [1.0 / (1 << i) for i in range(0, 33)]

def div_nr_v2 (N, D, G=None):


    bitlen = D.bit_length()
    k = bitlen
    #G =  1/(1 << k)
    G = LUT[k]




    change = 1
    G_prev = G
    G_new = G
    iter = 0

    while change > G/100000:
        G_new = G * (2-D*G)
        #print(f"Iteration {iter}: G = {G_new}")
        change = abs(G_new - G_prev)
        G_prev = G_new
        G = G_new
        iter += 1
    
    #print(f"Iteration {iter}: G = {G_new}")

    Q = trunc(N * G)
    R = N - D * Q

    if R >= D:
        Q += 1
        R -= D

    return Q, R, iter

#print(div_nr(24, 6))






"""

def div_nr_v1(N, D, G=0.1):

    change = 1
    G_prev = G
    G_new = G
    iter = 1

    while change > G/100000:
        G_new = G * (2-D*G)
        print(f"Iteration {iter}: G = {G_new}")
        change = abs(G_new - G_prev)
        G_prev = G_new
        G = G_new
        iter += 1

    Q = trunc(N * G)

    return Q , N - D * Q

#print(div_nr(17, 5, 0.1, 'R'))

"""



def div_repeat_subtraction(N, D):
    """Performs division using repeated subtraction."""
    if D == 0:
        raise ValueError("Division by zero is undefined.")
    quotient = 0
    remainder = N
    i = 1
    while remainder >= D:
        #print(f"Iteration {i}: remainder = {remainder}, quotient = {quotient}")
        remainder -= D
        quotient += 1
        i += 1
    #print(f"Iteration {i}: remainder = {remainder}, quotient = {quotient}")
    return quotient, remainder, i

def standard_division(a, b):
    """Performs standard integer division."""
    if b == 0:
        raise ValueError("Division by zero is undefined.")
    quotient = a // b
    remainder = a % b
    return quotient, remainder
