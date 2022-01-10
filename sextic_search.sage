"""
This module aims at finding curves defined over sextic extensions of prime fields.
"""

import sys
from multiprocessing import cpu_count, Pool
from traceback import print_exc

from utils import *

if sys.version_info[0] == 2:
    range = xrange


def find_curve(extension, extension_tower, psi_map, max_cofactor, small_order, wid=0, processes=1):
    r"""Yield curve constructed over a prime field extension.

    INPUT:

    - ``extension`` -- the field seen as a direct extension
    - ``extension_tower`` -- the field seen as an extension tower
    - ``psi_map`` -- an isomorphism from `extension` to `extension_tower`
    - ``max_cofactor`` -- the maximum cofactor for the curve order
    - ``small_order`` -- boolean indicating whether to look for small orders (254/255 bits).
            Overrides `max_cofactor` if set to `True`.
    - ``wid`` -- current job id (default 0)
    - ``processes`` -- number of concurrent jobs (default 1)

    OUTPUT:

    - ``extension`` -- the field extension
    - ``E`` -- the curve definition
    - ``g`` -- a generator of the large prime order subgroup
    - ``prime_order`` -- the prime order of the large subgroup generated by g
    - ``cofactor`` -- the cofactor of the curve
    - ``i`` -- the exponent of the extension primitive element defining the b coefficient
    - ``coeff_a`` -- the a coefficient of the curve in short Weierstrass form (always 1)
    - ``coeff_b`` -- the b coefficient of the curve in short Weierstrass form
    - ``rho_sec`` -- the Pollard-Rho security of the curve
    - ``k`` -- the embedding degree of the curve
    - ``twist_rho_sec`` -- the Pollard-Rho security of the twist

    """

    a = extension.primitive_element()
    p = extension.base_ring().order()
    for i in range(wid + 1, 1000000000, processes):
        sys.stdout.write(".")
        sys.stdout.flush()

        coeff_a = 1
        coeff_b = a**i

        E = EllipticCurve(extension, [coeff_a, coeff_b])

        n = E.count_points()
        prime_order = list(ecm.factor(n))[-1]
        cofactor = n // prime_order
        if small_order:
            if prime_order.nbits() < 254 or prime_order.nbits() > 255:
                continue
        elif cofactor > max_cofactor:
            continue

        sys.stdout.write("o")
        sys.stdout.flush()

        # TODO: use proper hash-to-curve algorithm
        bin = BinaryStrings()
        gen_x_bin = bin.encoding("Topos")
        gen_x = extension(int(str(gen_x_bin), 2))
        gen_y2 = (gen_x ^ 3 + gen_x + coeff_b)
        while True:
            if gen_y2.is_square():
                g = E((gen_x, gen_y2.sqrt()))
                g_ord = g.order()
                if g_ord >= prime_order:
                    sys.stdout.write("@")
                    sys.stdout.flush()
                    break
            gen_x += 1
            gen_y2 = (gen_x ^ 3 + gen_x + coeff_b)

        if g_ord != prime_order:
            g = cofactor * g

        (rho_sec, k) = curve_security(
            extension.cardinality(), n, prime_order)

        if k.nbits() < EMBEDDING_DEGREE_SECURITY:
            continue

        sys.stdout.write("+")
        sys.stdout.flush()

        if rho_sec < RHO_SECURITY:
            continue

        sys.stdout.write("~")
        sys.stdout.flush()

        extension_tower_polynomial_ring = extension_tower['x']
        x = extension_tower_polynomial_ring.gen()
        curve_polynomial = x ^ 3 + coeff_a * x + psi_map(coeff_b)

        extension_sec = sextic_extension_specific_security(
            E, curve_polynomial, n)
        if not extension_sec:
            continue

        # Factorization for calculating the embedding degree can be extremely slow
        # hence this check must be performed separately on potential candidates
        # outputted by the search algorithm.
        twist_rho_sec = twist_security_ignore_embedding_degree(
            extension.cardinality(), n)

        if twist_rho_sec < TWIST_SECURITY:
            continue

        yield (extension, E, g, prime_order, cofactor, i, coeff_a, coeff_b, rho_sec, k, twist_rho_sec)


def print_curve(prime, extension_degree, max_cofactor, small_order, wid=0, processes=1):
    r"""Print parameters of curves defined over a prime field extension

    INPUT:

    - ``prime`` -- the base prime defining Fp
    - ``extension_degree`` -- the targeted extension degree, defining Fp^n on which the curves will be constructed
    - ``max_cofactor`` -- the maximum cofactor for the curve order
    - ``small_order`` -- boolean indicating whether to look for small orders (254/255 bits).
            Overrides `max_cofactor` if set to `True`.
    - ``wid`` -- current job id (default 0)
    - ``processes`` -- number of concurrent jobs (default 1)

    """

    Fp = GF(prime)
    if wid == 0:
        info = f"\n{Fp}.\n"
    Fpx = Fp['x']
    factors = list(factor(Integer(extension_degree)))
    count = 1
    for n in range(len(factors)):
        degree = factors[n][0]
        for i in range(factors[n][1]):  # multiplicity
            poly_list = find_irreducible_poly(Fpx, degree)
            if poly_list == []:
                poly_list = find_irreducible_poly(Fpx, degree, use_root=True)
                if poly_list == []:
                    raise ValueError(
                        'Could not find an irreducible polynomial with specified parameters.')
            poly = poly_list[0]  # extract the polynomial from the list
            Fp = Fp.extension(poly, f"u_{n}{i}")
            if wid == 0:
                info += f"Modulus {count}: {poly}.\n"
                count += 1
            Fpx = Fp['x']

    if wid == 0:
        if small_order:
            info += f"Looking for curves with 254 or 255-bit prime order.\n"
        else:
            info += f"Looking for curves with max cofactor: {max_cofactor}.\n"
        print(info)
    extension, _phi, psi = make_finite_field(Fp)

    for (extension, E, g, order, cofactor, index, coeff_a, coeff_b, rho_security, embedding_degree, twist_rho_security) in find_curve(extension, Fp, psi, max_cofactor, small_order, wid, processes):
        coeff_b_prime = psi(coeff_b)
        E_prime = EllipticCurve(Fp, [1, coeff_b_prime])
        output = "\n\n\n"
        output += "# Curve with basefield seen as a direct extension\n"
        output += f"E(GF(({extension.base_ring().order().factor()})^{extension.degree()})) : y^2 = x^3 + x + {coeff_b} (b == a^{index})\n"
        output += f"\t\twith a = {extension.primitive_element()}\n"
        output += "# Curve with basefield seen as a towered extension\n"
        output += f"E'(GF(({Fp.base_ring().order().factor()})^{Fp.degree()})) : y^2 = x^3 + x + {coeff_b_prime}\n\n"
        output += f"E generator point: {g}\n"
        gx = g.xy()[0]
        gy = g.xy()[1]
        g_prime = E_prime(psi(gx), psi(gy))
        output += f"E' generator point: {g_prime}\n\n"
        output += f"Curve prime order: {order} ({order.nbits()} bits)\n"
        output += f"Curve cofactor: {cofactor}"
        if cofactor > 4:
            output += f" ( = {cofactor % 4} % 4 )"
        output += f"\nCurve security (Pollard-Rho): {'%.2f'%(rho_security)}\n"
        output += f"Curve embedding degree: {embedding_degree} (>2^{embedding_degree.nbits()-1}) \n"
        output += f"Twist security (Pollard-Rho): {'%.2f'%(twist_rho_security)}\n"
        # checked in find_curve
        output += f"Curve resistant to cover and decomposition attacks: True\n\n"
        print(output)
    return

########################################################################


def main():
    """Main function"""
    args = sys.argv[1:]
    processes = 1 if "--sequential" in args else cpu_count()
    small_order = "--small-order" in args
    strategy = print_curve
    help = "--help" in args
    args = [arg for arg in args if not arg.startswith("--")]

    if help:
        print("""
Cmd: sage sextic_search.sage [--sequential] [--small-order] <prime> <extension_degree> <max_cofactor>

Args:
    --sequential        Uses only one process
    --small-order       Looks for curves with 254 or 255-bit prime order (overrides cofactor)
    <prime>             A prime number, default 2^62 + 2^56 + 2^55 + 1
    <extension_degree>  The extension degree of the prime field, default 6
    <max_cofactor>      Maximum cofactor of the curve, default 64
""")
        return

    prime = int(args[0]) if len(
        args) > 0 else 4719772409484279809  # 2^62 + 2^56 + 2^55 + 1
    extension_degree = int(args[1]) if len(args) > 1 else 6
    max_cofactor = int(args[2]) if len(args) > 2 else 64

    if processes == 1:
        strategy(prime, extension_degree,
                 max_cofactor, small_order)
    else:
        print(f"Using {processes} processes.")
        pool = Pool(processes=processes)

        try:
            for wid in range(processes):
                pool.apply_async(
                    worker, (strategy, prime, extension_degree, max_cofactor, small_order, wid, processes))

            while True:
                sleep(1000)
        except (KeyboardInterrupt, SystemExit):
            pass
        finally:
            pool.terminate()


def worker(strategy, *args):
    res = []
    try:
        res = real_worker(strategy, *args)
    except (KeyboardInterrupt, SystemExit):
        pass
    except:
        print_exc()
    finally:
        return res


def real_worker(strategy, *args):
    return strategy(*args)


main()
