# Version pin matrix

Qiskit 2.x together with the packages later phases depend on. They are pinned in `uv.lock` (the `compat` dependency
group) and verified on **amd64 and arm64** by the `pin matrix` CI job (`make compat` locally).

| Package | Locked version | Used from | arm64 wheel |
|---|---|---|---|
| qiskit | 2.6.1 | P1 | ✅ abi3, manylinux_2_28 |
| qiskit-aer | 0.18.2 | P1 | ✅ manylinux_2_28 |
| numpy / scipy | 2.2.6 / 1.17.1 | P1 | ✅ |
| mthree | 3.0.0 | P9 (M3 readout mitigation) | ✅ **manylinux_2_34**: needs glibc ≥ 2.34 |
| mitiq | 1.1.0 | P9 (ZNE, CDR) | ✅ pure Python (pulls cirq-core 1.6) |
| qiskit-ibm-runtime | 0.51.0 | P7 (IBM provider) | ✅ pure Python |
| qiskit-ionq | 1.1.1 | P7 (IonQ simulator provider) | ✅ pure Python |
| qiskit-braket-provider | 0.27.4 | P7 (Braket local simulator) | ✅ pure Python |

Notes
- Container base images must provide glibc ≥ 2.34 (Debian 12 / Ubuntu 22.04 or newer) because of mthree on arm64.
- The `compat` group is not installed by default; P7/P9 move each package into the package that needs it.
- Renovate proposes updates; the pin-matrix job must stay green for both architectures before merging.
