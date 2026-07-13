#!/bin/bash
set -e

echo ""
echo "================================================================"
echo "STAGE 1: Environment and Dependency Setup"
echo "================================================================"
echo ""

# Make HEASoft work
export HEADAS=$PREFIX/heasoft/
source $HEADAS/headas-init.sh

# Set up variable to hold the path to the HEALpix source
export EXTERNAL_DIR=$SRC_DIR/external
export HEALPIX_DIR=$EXTERNAL_DIR/Healpix_3.50

# HEALpix wants a static cfitsio.a, but conda provides .so
# We fulfill the requirement with a symlink within the build prefix
if [ ! -f "$PREFIX/lib/libcfitsio.a" ]; then
    echo "Creating libcfitsio.a symlink for HEALPix..."
    ln -s "$PREFIX/lib/libcfitsio.so" "$PREFIX/lib/libcfitsio.a"
fi

echo ""
echo "================================================================"
echo "STAGE 2: Automated HEALPix Configuration & Build"
echo "================================================================"
echo ""

cd $HEALPIX_DIR

# Determine platform-specific tools and flags
if [[ "$target_platform" == osx-* ]]; then
    export F90_OS="Darwin"
    # Use Apple's system libtool to avoid collision with GNU libtool in the path
    export F90_AR="/usr/bin/libtool -static -s -o"
    export WLRPATH="-Wl,-rpath "
else
    export F90_OS="Linux"
    # Use the conda-provided 'ar' tool
    export F90_AR="$AR -rsv"
    export WLRPATH="-Wl,-R"
fi

echo "Configuring HEALPix for $F90_OS..."

F90_FC=$FC
F90_CC=$CC
F90_FFLAGS="-O3 -I$HEALPIX_DIR/include -DGFORTRAN -fno-second-underscore -fPIC"
F90_CFLAGS="-O3 -std=c99 -DgFortran -fPIC"
F90_MODDIR="-J"

# Replicate the 'editF90Makefile' function from hpxconfig_functions.sh
sed -e "s|^F90_FC.*$|F90_FC = $F90_FC|" \
    -e "s|^F90_FFLAGS.*$|F90_FFLAGS = $F90_FFLAGS|" \
    -e "s|^F90_LDFLAGS.*$|F90_LDFLAGS = -L$HEALPIX_DIR/lib -L$PREFIX/lib -lhealpix -lhpxgif -lcfitsio -lcurl $WLRPATH$PREFIX/lib|" \
    -e "s|^F90_CC.*$|F90_CC = $F90_CC|" \
    -e "s|^F90_CFLAGS.*$|F90_CFLAGS = $F90_CFLAGS|" \
    -e "s|^HEALPIX=.*$|HEALPIX = $HEALPIX_DIR|" \
    -e "s|^FITSDIR.*$|FITSDIR = $PREFIX/lib|" \
    -e "s|^LIBFITS.*$|LIBFITS = cfitsio|" \
    -e "s|^F90_BINDIR.*$|F90_BINDIR = $HEALPIX_DIR/bin|" \
    -e "s|^F90_INCDIR.*$|F90_INCDIR = $HEALPIX_DIR/include|" \
    -e "s|^F90_LIBDIR.*$|F90_LIBDIR = $HEALPIX_DIR/lib|" \
    -e "s|^F90_BUILDDIR.*$|F90_BUILDDIR = $HEALPIX_DIR/build|" \
    -e "s|^F90_AR.*$|F90_AR = $F90_AR|" \
    -e "s|^F90_FFTSRC.*$|F90_FFTSRC = healpix_fft|" \
    -e "s|^F90_MODDIR[[:space:]=].*$|F90_MODDIR = \"$F90_MODDIR\"|" \
    -e "s|^F90_MOD[[:space:]=].*$|F90_MOD = mod|" \
    -e "s|^F90_OS.*$|F90_OS = $F90_OS|" \
    -e "s|^F90_I8FLAG.*$|F90_I8FLAG = -fdefault-integer-8|" \
    -e "s|^F90_LIBSUFFIX.*$|F90_LIBSUFFIX = .a|" \
    -e "s|^ALL\(.*\) f90-void\(.*\)|ALL\1 f90-all\2|" \
    -e "s|^TESTS\(.*\) f90-void\(.*\)|TESTS\1 f90-test\2|" \
    -e "s|^CLEAN\(.*\) f90-void\(.*\)|CLEAN\1 f90-clean\2|" \
    -e "s|^DISTCLEAN\(.*\) f90-void\(.*\)|DISTCLEAN\1 f90-distclean\2|" \
    Makefile.in > Makefile

mkdir -p lib bin include build
echo "Generating healpix.pc..."
cat <<EOF > lib/healpix.pc
# HEALPix/F90 pkg-config file
prefix=$HEALPIX_DIR
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: HEALPix
Description: F90 library for HEALPix (eSASS DR1 Custom Build)
Version: 3_50
Requires: cfitsio >= 3.20
Libs: -L\${libdir} -lhealpix -lhpxgif
Cflags: -I\${includedir} -fopenmp -fPIC
EOF

echo "Starting HEALPix build..."
make

echo ""
echo "================================================================"
echo "STAGE 3: eSASS Configuration & Build"
echo "================================================================"
echo ""

export CC="${CC}"
export CXX="${CXX}"
export FC="${FC}"
export F77="${FC}"

cd $SRC_DIR/eSASS/autoconf

echo "Running autoreconf..."
autoreconf -fi -v

echo "Configuring eSASS..."
export ALL_ESASS_DIR=$PREFIX/eSASS4DR1/
export ESASS_PREFIX=$ALL_ESASS_DIR/eSASS
mkdir -p $ESASS_PREFIX

./configure \
    --prefix=$ESASS_PREFIX \
    --with-healpix=$HEALPIX_DIR \
    --with-headas=$HEADAS \
    --with-gsl=system \
    --with-lapack=system \
    --with-caldb=no \
    LDFLAGS="-L$PREFIX/lib -L$HEADAS/lib -Wl,-rpath,$PREFIX/lib -Wl,-rpath,$HEADAS/lib" \
    CPPFLAGS="-I$PREFIX/include" \
    CFLAGS="-I$PREFIX/include" \
    FFLAGS="-I$PREFIX/include" \
    FCFLAGS="-I$PREFIX/include"

echo "Starting eSASS build..."
make

echo "Installing eSASS..."
make install

#echo "Moving other eSASS components to host..."
# ------------- Moving top level information files --------------
cp $SRC_DIR/AUTHORS $ALL_ESASS_DIR
cp $SRC_DIR/COPYING $ALL_ESASS_DIR
cp $SRC_DIR/README.md $ALL_ESASS_DIR
# ---------------------------------------------------------------

# --------------- Moving eSASS information files ----==----------
cp $SRC_DIR/eSASS/AUTHORS $ESASS_PREFIX
cp $SRC_DIR/eSASS/COPYING $ESASS_PREFIX
# ---------------------------------------------------------------

# --------------- Moving the 'external' directory ---------------
export EXTERNAL_INSTALL_DIR=$ALL_ESASS_DIR/external/
mkdir -p $EXTERNAL_INSTALL_DIR
cp -r $EXTERNAL_DIR $EXTERNAL_INSTALL_DIR
# ---------------------------------------------------------------

# --------------- Moving the 'erosita' directory ----------------
cp -r $SRC_DIR/eSASS/erosita $ESASS_PREFIX/erosita
# ---------------------------------------------------------------

# ----------------- Moving the 'sass' directory -----------------
cp -r $SRC_DIR/eSASS/sass $ESASS_PREFIX/sass
# ---------------------------------------------------------------

# --------------- Moving the 'scripts' directory ----------------
cp -r $SRC_DIR/eSASS/scripts $ESASS_PREFIX/scripts
# ---------------------------------------------------------------

echo ""
echo "================================================================"
echo "STAGE 4: Creating Conda Activation Scripts"
echo "================================================================"
echo ""

mkdir -p $PREFIX/etc/conda/activate.d
mkdir -p $PREFIX/etc/conda/deactivate.d

echo "Writing activation scripts..."
cat <<EOF > $PREFIX/etc/conda/activate.d/post_heasoft_esass_activate.sh
#!/bin/bash

# Point to the eSASS4DR1/eSASS subdirectory
export ESASS_DIR=\$CONDA_PREFIX/eSASS4DR1/eSASS

# Ensure SASS_ROOT points to the internal esass folder
#export SASS_ROOT=\$ESASS_DIR

# Check if the user is running Zsh
if [ -n "$ZSH_VERSION" ]; then
    source "\$ESASS_DIR/bin/esass-init.zsh"
# Otherwise, default to the Bash script
else
    source "\$ESASS_DIR/bin/esass-init.sh"
fi

echo "Activating eSASS in \$ESASS_DIR"
EOF

cat <<EOF > $PREFIX/etc/conda/activate.d/post_heasoft_esass_activate.csh
#!/bin/csh

# Point to the eSASS4DR1/eSASS subdirectory
setenv ESASS_DIR \$CONDA_PREFIX/eSASS4DR1/eSASS

# Ensure SASS_ROOT points to the internal esass folder
#setenv SASS_ROOT \$ESASS_DIR

# Source the C shell init script
source \$ESASS_DIR/bin/esass-init.csh

echo "Activating eSASS in \$ESASS_DIR"
EOF


echo "Writing deactivation script..."
cat <<EOF > $PREFIX/etc/conda/deactivate.d/esass_deactivate.sh
#!/bin/bash
unset SASS_BIN_ROOT SASS_SETUP SASS_ROOT E_ROOT CALDB CALDBCONFIG
unset SASS_TEMPLATES E_MOD E_LIB SASS_CALVERS SASS_DIR
EOF

echo ""
echo "================================================================"
echo "Build and installation of eSASS DR1 complete!"
echo "================================================================"
echo ""
