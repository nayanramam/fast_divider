from div_algorithms import *

import random
import math

def test_divider(divider_func, a, b, expected_quotient, expected_remainder):
    quotient, remainder, iterations = divider_func(a, b)
    print(f"Quotient: {quotient}, Remainder: {remainder}, Iterations: {iterations}")
    assert quotient == expected_quotient, f"Expected quotient {expected_quotient}, got {quotient}"
    assert remainder == expected_remainder, f"Expected remainder {expected_remainder}, got {remainder}"
    print(f"Iterations: {iterations}")
    return iterations


if __name__ == "__main__":
    # Example test cases
    total_iter_rs = 0
    total_iter_nr = 0
    total_iter_nr_v2 = 0
    total_iter_gs = 0
    for i in range(100):
        a = random.randint(1, 2**32 - 1)
        b = random.randint(1, 2**32 - 1)
        expected_quotient = a // b
        expected_remainder = a % b

        

        print(f"\nTEST {i+1}: \nTesting {a} / {b}: expected quotient {expected_quotient}, expected remainder {expected_remainder}")

        #print("Standard Division:")
        #test_divider(standard_division, a, b, expected_quotient, expected_remainder)

        #print("Division by Repeated Subtraction:")
        #total_iter_rs += test_divider(div_repeat_subtraction, a, b, expected_quotient, expected_remainder)

        print("Division by Newton-Raphson (LUT):")
        total_iter_nr += test_divider(div_nr, a, b, expected_quotient, expected_remainder)

        print("Division by Newton-Raphson v2:")
        total_iter_nr_v2 += test_divider(div_nr_v2, a, b, expected_quotient, expected_remainder)

        print("Division by Gold-Schmidt:")
        total_iter_gs += test_divider(div_gs_v3, a, b, expected_quotient, expected_remainder)

    print(f"Total iterations - Repeated Subtraction: {total_iter_rs}, Newton-Raphson (LUT): {total_iter_nr}, Newton-Raphson v2: {total_iter_nr_v2}, Gold Schmidt: {total_iter_gs}")


    # Fixed test cases
    #test_divider(standard_division, 10, 3, 3, 1)
    #test_divider(standard_division, 20, 4, 5, 0)
    #test_divider(standard_division, 7, 2, 3, 1)

    print("All tests passed!")
