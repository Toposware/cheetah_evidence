"""
This module aims at finding curves defined over sextic extensions of prime fields.
"""

import sys
from multiprocessing import cpu_count, Pool
from traceback import print_exc
from itertools import combinations_with_replacement

from utils import *

if sys.version_info[0] == 2:
    range = xrange


def make_finite_field(k):
    r""" Return the finite field isomorphic to this field.

    INPUT:

    - ``k`` -- a finite field

    OUTPUT: a tuple `(k_1,\phi,\xi)` where `k_1` is a 'true' finite field,
    `\phi` is an isomorphism from `k` to `k_1` and `\xi` is an isomorphism
    from `k_1` to `k`.

    This function is useful when `k` is constructed as a tower of extensions
    with a finite field as a base field.

    Adapted from https://github.com/MCLF/mclf/issues/103.

    """

    assert k.is_field()
    assert k.is_finite()
    # TODO: partially solved sage9.4 issue but still failing for higher extensions (wrong isomorphic field)
    if k.base_ring().is_prime_field():
        return k, k.hom(k.gen(), k), k.hom(k.gen(), k)
    else:
        k0 = k.base_field()
        G = k.modulus()
        assert G.parent().base_ring() is k0
        k0_new, phi0, _ = make_finite_field(k0)
        G_new = G.map_coefficients(phi0, k0_new)
        k_new = k0_new.extension(G_new.degree())

        alpha = G_new.roots(k_new)[0][0]
        Pk0 = k.cover_ring()
        Pk0_new = k0_new[Pk0.variable_name()]
        psi1 = Pk0.hom(phi0, Pk0_new)
        psi2 = Pk0_new.hom(alpha, k_new)
        psi = psi1.post_compose(psi2)
        # psi: Pk0 --> k_new
        phi = k.hom(Pk0.gen(), Pk0, check=False)
        phi = phi.post_compose(psi)

        k_inv = k0.base_ring()
        phi0_inv = k_inv.hom(k_inv.gen(), k_inv)
        G_new_inv = k_new.modulus().map_coefficients(phi0_inv, k0_new)
        alpha_inv = G_new_inv.roots(k)[0][0]
        phi_inv = k_new.hom(alpha_inv, k)

        return k_new, phi, phi_inv


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
        output += f"Curve resistant to extension-specific attacks: True\n\n"
        print(output)
    return


def find_irreducible_poly(ring, degree, use_root=False, max_coeff=2, output_all=False):
    r"""Return a list of irreducible polynomials with small and few coefficients.

    INPUT:

    - ``ring`` -- a polynomial ring
    - ``degree`` -- the degree of the irreducible polynomial
    - ``use_root`` -- boolean indicating whether using only the ring base field elements as coefficients
                      or using also an element not belonging to the base field (default False)
    - ``max_coeff`` -- maximum absolute value for polynomial coefficients
    - ``output_all`` -- boolean indicating whether outputting only one polynomial or all (default False)

    OUTPUT: a list of irreducible polynomials.

    The default behaviour, to return a single polynomial, still outputs a list of length 1 to keep the
    function output consistent when `output_all == True`.

    """

    x = ring.gen()

    set_coeffs_1 = set(combinations_with_replacement(
        range(-max_coeff, max_coeff), degree))
    set_coeffs_2 = set(combinations_with_replacement(
        reversed(range(-max_coeff, max_coeff)), degree))
    set_coeffs = set_coeffs_1.union(set_coeffs_2)

    list_poly = []
    for coeffs in set_coeffs:
        p = x ^ degree
        for n in range(len(coeffs)):
            p += coeffs[n]*x ^ n
        if p.is_irreducible():
            list_poly.append(p)

    if use_root:
        root = ring.base().gen()
        for regular_coeffs in set_coeffs:
            p = x ^ degree
            for n in range(len(regular_coeffs)):
                p += regular_coeffs[n]*x ^ n
            for special_coeffs in set_coeffs:
                q = p
                for n in range(len(special_coeffs)):
                    q += root * special_coeffs[n]*x ^ n
                if q.is_irreducible():
                    list_poly.append(q)
                    # Exhaustive search usually becomes too heavy with this,
                    # hence stop as soon as one solution is found
                    if not output_all:
                        return min(list_poly, key=lambda t: len(t.coefficients()))

    if output_all or list_poly == []:
        return list_poly
    else:
        return [min(list_poly, key=lambda t: len(t.coefficients()))]


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
