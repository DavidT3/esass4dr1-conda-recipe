# Conda package for eSASS4DR1

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
  --keep-build
```