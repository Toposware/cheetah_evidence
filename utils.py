from constants import CURVE_COFACTOR, CURVE_PRIME_ORDER
from sage.all import *
from termcolor import colored
from itertools import combinations_with_replacement

# Bitlength thresholds for different attacks security considerations
RHO_SECURITY = 125
EXTENSION_SECURITY = 125
TWIST_SECURITY = 100
EMBEDDING_DEGREE_SECURITY = 200
# For Pollard-Rho security analysis
PI_4 = (pi/4).numerical_approx()


######################
#  HELPER FUNCTIONS  #
######################

def make_finite_field(k):
    r""" Return the finite field isomorphic to this field.

    INPUT:

    - ``k`` -- a finite field

    OUTPUT: a tuple `(k_1,\phi,\xi)` where `k_1` is a 'true' finite field,
    `\phi` is an isomorphism from `k` to `k_1` and `\xi` is an isomorphism
    from `k_1` to `k`.

    ***NOTE***: `\phi` and `\psi` are not inverses of each other.

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
        p = x ** degree
        for n in range(len(coeffs)):
            p += coeffs[n]*x ** n
        if p.is_irreducible():
            list_poly.append(p)

    if use_root:
        root = ring.base().gen()
        for regular_coeffs in set_coeffs:
            p = x ** degree
            for n in range(len(regular_coeffs)):
                p += regular_coeffs[n]*x ** n
            for special_coeffs in set_coeffs:
                q = p
                for n in range(len(special_coeffs)):
                    q += root * special_coeffs[n]*x ** n
                if q.is_irreducible():
                    list_poly.append(q)
                    # Exhaustive search usually becomes too heavy with this,
                    # hence stop as soon as one solution is found
                    if not output_all:
                        return [min(list_poly, key=lambda t: len(t.coefficients()))]

    if output_all or list_poly == []:
        return list_poly
    else:
        return [min(list_poly, key=lambda t: len(t.coefficients()))]


def display_result(
        p_isprime,
        q_isprime,
        q_nbits,
        is_pollard_rho_secure,
        is_mov_secure,
        e_security,
        twist_is_pollard_rho_secure,
        twist_is_mov_secure,
        t_security,
        is_genus_2_secure,
        is_genus_3_h_secure,
        is_genus_3_nh_secure,
        is_ghs_secure):
    r""" Print the final security evaluation to the terminal

    INPUT:

    - ``p_isprime`` -- a boolean indicating if p is prime
    - ``q_isprime`` -- a boolean indicating if q is prime
    - ``q_nbits`` -- the number of bits of q
    - ``is_pollard_rho_secure`` -- a boolean indicating if the curve is secure against the Pollard-Rho attack
    - ``is_mov_secure`` -- a boolean indicating if the curve is secure against the MOV attack
    - ``e_security`` -- a tuple indicating the attack cost on the curve of Pollard-Rho and the embedding degree
    - ``twist_is_pollard_rho_secure`` -- a boolean indicating if the twist is secure against the Pollard-Rho attack
    - ``twist_is_mov_secure`` -- a boolean indicating if the twist is secure against the MOV attack
    - ``t_security`` -- a tuple indicating the attack cost on the twist of Pollard-Rho and the embedding degree
    - ``is_genus_2_secure`` -- a boolean indicating if the curve is secure against a genus 2 cover attack
    - ``is_genus_3_h_secure`` -- a boolean indicating if the curve is secure against a hyperelliptic genus 3 cover attack
    - ``is_genus_3_nh_secure`` -- a boolean indicating if the curve is secure against a non-hyperelliptic genus 3 cover attack
    - ``is_ghs_secure`` -- a boolean indicating if the curve is secure against the GHS attack

    """

    def color(bool):
        return colored(bool, 'green' if bool else 'red')

    output = "-----------------------------------------------------------------------------------------\n"
    output += "|                                                                                       |\n"
    output += "|\t\t\t    -------------------------------\t\t\t\t|\n"
    output += "|\t\t\t    |  Cheetah Security Analysis  |\t\t\t\t|\n"
    output += "|\t\t\t    -------------------------------\t\t\t\t|\n"
    output += "|                                                                                       |\n"
    output += "|\t\t\t      E(F_p^6): y^2 = x^3 + x + B\t\t\t\t|\n"
    output += f"|\t\t\t   #E = q.h, q {q_nbits}-bit subgroup order\t\t\t\t|\n"
    output += "|                                                                                       |\n"
    output += f"|\tp is prime: {color(p_isprime)}\t\t\t\t\t\t\t\t|\n"
    output += f"|\tq is prime: {color(q_isprime)}\t\t\t\t\t\t\t\t|\n"
    output += f"|\tcurve is secure against the Pollard-Rho attack: {color(is_pollard_rho_secure)} ({e_security[0]:.2f} bits)\t\t|\n"
    output += f"|\tcurve is secure against MOV attack: {color(is_mov_secure)} (curve embedding degree > 2^{e_security[1].nbits()})\t|\n"
    output += f"|\ttwist is secure against the Pollard-Rho attack: {color(twist_is_pollard_rho_secure)} ({t_security[0]:.2f} bits)\t\t|\n"
    output += f"|\ttwist is secure against MOV attack: {color(twist_is_mov_secure)} (twist embedding degree > 2^{t_security[1].nbits()})\t|\n"
    output += f"|\tcurve is secure against genus 2 cover attack: {color(is_genus_2_secure)}\t\t\t\t|\n"
    output += f"|\tcurve is secure against genus 3 hyperelliptic cover attack: {color(is_genus_3_h_secure)}\t\t|\n"
    output += f"|\tcurve is secure against genus 3 non-hyperelliptic cover attack: {color(is_genus_3_nh_secure)}\t\t|\n"
    output += f"|\tcurve is secure against GHS attack: {color(is_ghs_secure)}\t\t\t\t\t|\n"
    output += "|                                                                                       |\n"
    output += "-----------------------------------------------------------------------------------------\n"

    print(output)


##############################
#  CURVE SECURITY FUNCTIONS  #
##############################

def curve_security(p, q, main_factor=0, main_factor_m1_factors_list=[]):
    r""" Return the estimated cost of running Pollard-Rho against
    the curve main subgroup, and the curve embedding degree.

    INPUT:

    - ``p`` -- the curve basefield
    - ``q`` -- the curve order
    - ``main_factor`` -- the largest prime factor of the curve order. This parameter is optional
        and can be given to speed-up calculations. (default 0)
    - ``main_factor_m1_factors_list`` -- the factorization of `main_factor` - 1.
        This parameter is optional and can be given to speed-up calculations. (default [])

    OUTPUT: a tuple `(rho_sec, k)` where `rho_sec` is the estimated cost of running
    Pollard-Rho attack on the curve, and `k` is the curve embedding degree.
    """

    # Providing directly the main factor of q allows to speed up calculations
    r = main_factor if main_factor != 0 else factor(q)[-1][0]
    return (log(PI_4 * r, 4), embedding_degree(p, r, main_factor_m1_factors_list))


def embedding_degree(p, r, rm1_factors_list=[]):
    r""" Return the curve embedding degree.

    INPUT:

    - ``p`` -- the curve basefield
    - ``r`` -- the order of the large prime subgroup of the curve
    - ``rm1_factors_list`` -- the factorization of `r` - 1
        This parameter is optional and can be given to speed-up calculations. (default [])

    OUTPUT: the embedding degree `d` of the curve, as `Integer`.
    """
    assert gcd(p, r) == 1
    Z_r = Integers(r)
    u = Z_r(p)
    d = r-1
    factors = rm1_factors_list if rm1_factors_list != [] else factor(d)
    for (f, _multiplicity) in factors:
        while d % f == 0:
            if u**(d/f) != 1:
                break
            d /= f

    return Integer(d)


def twist_security(p, q, main_factor_of_2pp1mq=0, main_factor_of_2pp1mq_m1_factors_list=[]):
    r""" Return the estimated cost of running Pollard-Rho against
    the twist of the curve main subgroup, and the twist embedding degree.

    INPUT:

    - ``p`` -- the curve basefield
    - ``q`` -- the curve order
    - ``main_factor_of_2pp1mq`` -- the largest prime factor of the twist order (2(p+1) - q). 
        his parameter is optional and can be given to speed-up calculations. (default 0)
    - ``main_factor_of_2pp1mq_m1_factors_list`` -- the factorization of `main_factor_of_2pp1mq` - 1.
        This parameter is optional and can be given to speed-up calculations. (default [])

    OUTPUT: a tuple `(rho_sec, k)` where `rho_sec` is the estimated cost of running
    Pollard-Rho attack on the twist, and `k` is the twist embedding degree.
    """

    return curve_security(p, 2*(p+1) - q, main_factor_of_2pp1mq, main_factor_of_2pp1mq_m1_factors_list)


def twist_security_ignore_embedding_degree(p, q, main_factor_of_2pp1mq=0):
    r""" Return the estimated cost of running Pollard-Rho against the twist of the curve main subgroup.

    INPUT:

    - ``p`` -- the curve basefield
    - ``q`` -- the curve order
    - ``main_factor_of_2pp1mq`` -- the largest prime factor of the twist order (2(p+1) - q). 
        his parameter is optional and can be given to speed-up calculations. (default 0)

    OUTPUT: the estimated cost of running Pollard-Rho attack on the twist.
    """

    r = main_factor_of_2pp1mq if main_factor_of_2pp1mq != 0 else factor(
        2*(p+1) - q)[-1][0]
    return log(PI_4 * r, 4)


def sextic_extension_specific_security(curve, curve_polynomial, number_points=0):
    r""" Return whether the given `curve` is resistant to extension specific attacks, namely:

        - genus 2 cover attacks
        - genus 3 hyperelliptic cover attacks
        - genus 3 non-hyperelliptic cover attacks
        - GHS attack

    INPUT:

    - ``curve`` -- the elliptic curve
    - ``curve_polynomial`` -- the elliptic curve defining polynomial f in the Weierstrass equation y^2 = f(x)
    - ``number_points`` -- the number of points of the elliptic curve.
        This parameter is optional and can be given to speed-up calculations. (default 0)

    OUTPUT: a boolean indicating whether the given `curve` is resistant to the attacks.
    """

    sec_g2 = genus_2_cover_security(curve)
    sec_g3_h = genus_3_hyperelliptic_cover_security(curve, number_points)
    sec_g3_nh = genus_3_hyperelliptic_cover_security(curve)
    sec_ghs = ghs_security(curve_polynomial)

    return sec_g2 and sec_g3_h and sec_g3_nh and sec_ghs


def genus_2_cover_security(curve):
    r""" Return whether the given `curve` is resistant to genus 2 cover attacks.

    INPUT:

    - ``curve`` -- the elliptic curve

    OUTPUT: a boolean indicating whether the given `curve` is resistant to genus 2 cover attacks.
    """

    n = curve.count_points()
    # We don't perform any check on the j-invariant because of the
    # limitations of Sagemath with extension based elliptic curves.
    # Hence having an odd number of points directly lead to a "weak"
    # curve here.
    two_torsion_rank = curve.two_torsion_rank()
    return two_torsion_rank != 2 and (n % 2 == 1 or True)


def genus_3_hyperelliptic_cover_security(curve, number_points=0):
    r""" Return whether the given `curve` is resistant to genus 3 hyperelliptic cover attacks.

    INPUT:

    - ``curve`` -- the elliptic curve
    - ``number_points`` -- the number of points of the elliptic curve.
        This parameter is optional and can be given to speed-up calculations. (default 0)

    OUTPUT: a boolean indicating whether the given `curve` is resistant to genus 3 hyperelliptic cover attacks.
    """

    n = number_points if number_points != 0 else curve.count_points()
    if n % 4 == 0:
        return p.nbits() * 5.0/3 > EXTENSION_SECURITY
    return True


def genus_3_nonhyperelliptic_cover_security(curve):
    r""" Return whether the given `curve` is resistant to genus 3 non-hyperelliptic cover attacks.

    INPUT:

    - ``curve`` -- the elliptic curve

    OUTPUT: a boolean indicating whether the given `curve` is resistant to genus 3 non-hyperelliptic cover attacks.
    """

    q = curve.base_ring().characteristic() ** 2
    # Kim Laine and Kristin Lauter. Time-memory trade-offs for index calculus
    # in genus 3. Journal of Mathematical Cryptology, 9(2):95-114, 2015
    return log(1.23123 * log(q, 2) ** 2 * q, 2).numerical_approx() > EXTENSION_SECURITY


def ghs_security(curve_polynomial):
    r""" Return whether the given `curve` is resistant to the GHS attack.

    INPUT:

    - ``curve_polynomial`` -- the elliptic curve defining polynomial f in the Weierstrass equation y^2 = f(x)

    OUTPUT: a boolean indicating whether the given `curve` is resistant to the GHS attack.
    """

    p = curve_polynomial.base_ring().characteristic()
    roots = curve_polynomial.roots(multiplicities=false)
    if roots != []:
        for root in roots:
            if (root ** (p**2) in roots) or (root ** (p**3) in roots):
                return p.nbits() * 8.0 / 3 > EXTENSION_SECURITY
    return True
