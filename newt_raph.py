from math import trunc

def div_nr(N, D, G, O):
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

    if O == 'Q':
        return Q
    elif O == 'R':
        return N - D * Q
    else:
        raise ValueError("Invalid output option")

print(div_nr(17, 5, 0.1, 'R'))