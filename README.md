# Conda package for eSASS4DR1

This repository contains a Conda recipe for eROSITA's eSASSDR1 software. It supports multiple HEASoft versions (6.35.* and 6.36.*) and architectures (Linux-64, macOS-ARM64, macOS-64).

## Build Patches and Justifications

To ensure stability and compatibility in a Conda environment, several patches are applied to the eSASS source code during the build:

## Build Patches and Justifications

To ensure stability, scientific accuracy, and compatibility in a Conda environment, several patches are applied to the eSASS source code during the build. These patches address critical issues ranging from hardcoded paths to fatal memory corruption bugs.

### 1. `0001-fix-macos-paths-and-static-linking.patch`
- **Reason**: The original eSASS `configure.ac` contained hardcoded library search paths pointing to `/usr/local/`, Homebrew, and MacPorts locations (e.g., for `ncurses` and `readline`). This violates Conda's environment isolation, as it can cause the compiler to link against system libraries instead of the ones provided in the Conda prefix, leading to ABI mismatches and unportable packages.
- **Fix**: Removed all hardcoded system paths. The build now strictly uses libraries provided by the Conda environment (`$PREFIX`).
- **Additional Fix**: Removed a forced `-static-libgfortran` flag on macOS. Conda environments are designed for dynamic linking of the Fortran runtime; forcing a static link can lead to multiple copies of the runtime being loaded if other dependencies (like HEASoft) use the dynamic version, which often causes crashes.

### 2. `0002-fix-caldb-makefile-syntax.patch`
- **Reason**: The original `setup/Makefile.am` had several issues that prevented it from working correctly with standard `make install` procedures, particularly regarding the handling of documentation and the `ebarycen` task.
- **Fix**: 
    - Corrected the paths used for the `ebarycen` task so it can be correctly installed into the binary directory.
    - Updated the documentation installation logic to use `install-data-hook`, ensuring that HTML help files are correctly copied to the `$PREFIX/doc` directory in a way that is compatible with `DESTDIR` based builds used by Conda.

### 3. `0003-modify-esass-init-scripts.patch`
- **Reason**: By default, eSASS's initialization scripts (`esass-init.sh/zsh/csh`) attempt to automatically source the HEASoft environment. In a Conda setup, HEASoft is a separate package with its own activation scripts. Having eSASS "reach out" and re-initialize HEASoft can cause environment pollution and circular dependencies.
- **Fix**: Removed the automatic HEASoft setup. Sourcing the eSASS environment now assumes HEASoft is already active (which it is, via Conda's `activate.d` scripts).
- **Enhancement**: Added robust checks for the `CALDB` environment variable. If `CALDB` is not set, the script now provides a helpful warning and example of how to configure it manually, as the calibration database is not bundled with the Conda package.

### 4. `0004-fix-memory-corruption-and-initialize-indices.patch`
- **Reason**: This patch addresses a fatal memory corruption bug that was exposed during the transition to automated builds on GitHub Actions. The bug manifested as a `Fortran runtime error: Index '70694' of dimension 1 of array 'myeventfile...%xd' above upper bound of 53625` in the `ermldet` task.
- **The Trigger**: The failure was triggered by the move to a more modern and strict compiler toolchain (**Gfortran 15**) in a highly constrained environment (GitHub Actions **macOS M1** runners).
- **The "Luck" Factor (M1 vs M3)**: 
    - **Local M3 (Success)**: When built locally on an Apple Silicon M3 with automatic compiler selection, the software appeared to pass its tests. This was a case of "silent corruption"—the stack and heap layout produced by the compiler on the M3 placed enough padding or non-critical data adjacent to the buggy regions that the memory corruption didn't trigger a fatal crash.
    - **GHA M1 (Fail)**: The GitHub Action runner uses the M1 architecture. The specific stack frame layout produced by Gfortran 15 on this architecture was "unlucky"—the memory being corrupted hit critical loop control variables. This caused the deterministic `70694` error to occur on every single run, regardless of whether it was run on GHA or the resulting package was installed back on an M3.
- **Detailed Fixes**:
    - **Stack Buffer Overflow**: In `slib_calc_space_mod.f90`, the code defined a fixed-size stack buffer `integer, dimension(10000) :: listpix` to hold pixel indices returned by HEALPix. For standard eSASS skytiles, the HEALPix search often returns more than 10,000 results. This caused a buffer overflow on the stack, deterministically overwriting the adjacent 4-byte loop index variable with parts of a HEALPix pixel ID. The patch increases this buffer to **50,000** elements, providing safe headroom for standard operations.
    - **Uninitialized Memory "Time Bomb"**: In `slib_data_evt_mod.f90`, the code allocates the `INDEX1` and `INDEX2` mapping arrays. These arrays are crucial for mapping HEALPix pixels to event list positions. We discovered that the lines intended to zero-initialize these arrays were **commented out** in the original source code. If a pixel returned by HEALPix contained no events, the software would read uninitialized "garbage" memory from the heap. The patch un-comments these lines to ensure that empty pixels correctly return an index of `0`, preventing illegal memory accesses.

## Build Configuration Notes

### HEALPix Integer ABI (32-bit vs 64-bit)
In `recipe/build.sh`, we explicitly **avoid** forcing the `-fdefault-integer-8` flag during the HEALPix build. While the "official" eSASS Makefile sometimes defines this flag, our analysis showed that it is not consistently applied to the core routines eSASS interfaces with. Keeping HEALPix at the standard 32-bit integer size ensures a stable ABI match with eSASS, HEASoft, and other standard Conda libraries, preventing the memory mangling issues observed in early GitHub Action build attempts.

## Notes to self

The conda environment I made for building is `rattler-conda-build`

Need to increase the file limit for the build to work:

```bash
ulimit -n 16000
```


In theory the build process is triggered (from here) by:

```bash
cd recipe

rattler-build build \
  --recipe recipe.yaml \
  -c https://heasarc.gsfc.nasa.gov/FTP/software/conda/ \
  -c conda-forge 
```

OR WITH DEBUG ON (WILL DEFINITELY NEED) - this leaves the temporary build directory intact:

```bash
cd recipe

rattler-build build \
  --recipe recipe.yaml \
  -c https://heasarc.gsfc.nasa.gov/FTP/software/conda/ \
  -c conda-forge \
  --variant heasoft_version="6.35.*" \
  --variant c_compiler_version="20.*" \
  --variant cxx_compiler_version="20.*" \
  --variant fortran_compiler_version="==14.2.0" \
  --keep-build
```


```bash
cd recipe

rattler-build build \
  --recipe recipe.yaml \
  -c https://heasarc.gsfc.nasa.gov/FTP/software/conda/ \
  -c conda-forge \
  --variant heasoft_version="6.36.*" \
  --keep-build
```

```bash
rattler-build build \
  --recipe recipe.yaml \
  -c https://heasarc.gsfc.nasa.gov/FTP/software/conda/ \
  -c conda-forge \
  --variant heasoft_version="6.36.*" \
  --variant c_compiler_version="22.*" \
  --variant cxx_compiler_version="22.*" \
  --variant fortran_compiler_version="15.*" \
  --keep-build
```