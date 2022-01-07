# cheetah_evidence

Evidence of the security of the Cheetah elliptic curve, and search algorithm for elliptic curves based on sextic extensions of prime fields.

## Description

This repository contains a search algorithm to generate curves over sextic extensions of prime fields. It considers both regular attacks on
generic elliptic curve constructions (Pollard-Rho attack, twist attack, MOV attack, ...) as well as specific attacks leveraging the structure
of the curve basefield defined as an extension tower of final degree 6, such as cover and decomposition attacks. The search algorithm aims at
finding curves susceptible to provide close to 128 bits of security with the known state-of-the-art attacks on these special elliptic curves.

As a consequence, the search algorithm (in particular the portion dealing with the cover and decomposition attacks) should be modified before
targeting other security levels (192 bits or 256 bits).

**NOTE**: Experimental results have shown limitations in Sagemath factorization algorithms for computing the embedded degree of some curve twists.
Hence, in order to prevent running time clogging, only Pollard-Rho security against the twists is being checked. Making sure that their embedding
degree is also sufficiently large should be done on the potential candidates the search algorithm may output.

A result of this search algorithm is Cheetah, an elliptic-curve defined over a sextic extension of the prime field of charateristic
p = 2<sup>62</sup> + 2<sup>56</sup> + 2<sup>55</sup> + 1. To verify its security level, one can run the `verify.sage` script. Cheetah is the first candidate displayed from the `sextic_search.sage` script when running in sequential mode (argument `--sequential`) with the additional `--small-order` argument activated.

**NOTE**: Running in sequential mode guarantees to have deterministic ordering of the output, but at the cost of a much slower search. To benefit from multithreading, one can remove the `--sequential` argument, allowing Sage to
use as many parallel threads as possible.

## Usage

To find an elliptic curve on a field extension GF(2^61 - 1)^6 with cofactor <= 8:
```bash
sage sextic_search.sage 2305843009213693951 8
```

---

To find a prime-order elliptic curve on a field extension GF(2^61 - 1)^6:
```bash
sage sextic_search.sage 2305843009213693951 1
```

---

To find an elliptic curve on a field extension GF(2^62 + 2^56 + 2^55 + 1)^6 with small prime order (i.e. 254 or 255 bit long):
```bash
sage sextic_search.sage 4719772409484279809 --small-order
```

---

To perform security checks on the Cheetah curve:
```bash
sage verify.sage
```
