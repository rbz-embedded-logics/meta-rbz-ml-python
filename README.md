# meta-rbz-ml-python

Capa opcional sobre `meta-rbz` que añade a `rbz-image-ml` la pila Python de ML compilada en Yocto.
Si no se añade a `bblayers.conf`, `rbz-image-ml` queda igual que en `meta-rbz`.

| Paquete | Versión | Origen |
|---|---|---|
| python3-pyside6 / python3-shiboken6 | 6.11.1 | recetas de meta-qt6 6.11.1 (compila con Qt 6.11.0) |
| python3-scipy | 1.17.1 | meta-python-ai |
| python3-pytorch | 2.10.0 | meta-python-ai |
| python3-torchvision | 0.25.0 | meta-python-ai |
| python3-ultralytics | 8.4.19 | meta-python-ai |

## Requisitos

1. `meta-python-ai` en el commit `9f5bcb0d266c49ff1f5e517b822bbf97387f709c` (abril 2026, coincide con
   el oe-core del manifest; las versiones posteriores usan la sintaxis de licencias SPDX `AND`/`OR`
   que el oe-core de wrynose no acepta):

       cd sources
       git clone https://github.com/zboszor/meta-python-ai
       git -C meta-python-ai checkout 9f5bcb0d266c49ff1f5e517b822bbf97387f709c

   O en el manifest:

       <remote name="zboszor" fetch="https://github.com/zboszor"/>
       <project name="meta-python-ai" remote="zboszor" path="sources/meta-python-ai"
                revision="9f5bcb0d266c49ff1f5e517b822bbf97387f709c" upstream="master"/>

2. `gfortran` en el host (SciPy compila también una versión nativa):

       sudo apt install gfortran

3. Con el manifest `imx-6.18.20-2.0.0-rbz-ml-python.xml`, `rbz-setup-release.sh` añade los puntos 3 y 4
   automáticamente si existen `sources/meta-python-ai` y `sources/meta-rbz-ml-python`. A mano, `bblayers.conf`:

       BBLAYERS += "${BSPDIR}/sources/meta-python-ai"
       BBLAYERS += "${BSPDIR}/sources/meta-rbz-ml-python"

4. `local.conf`, torchvision depende de ffmpeg:

       LICENSE_FLAGS_ACCEPTED += "commercial_ffmpeg"

## Qué cambia esta capa

- `conf/layer.conf`: activa Fortran (`FORTRAN`, `libquadmath`, `gfortran` en `HOSTTOOLS`) y `CAN_USE_PYSIDE6`.
- `recipes-python/pyside6`: recetas de PySide6 6.11.1 (la 6.11.0 no soporta clang 22), sin los módulos de QtWebEngine.
- `python3-pytorch_%.bbappend`: `virtual/mesa` en lugar de `mesa`, sin Vulkan (shaderc no compila con el glslang 1.3 de NXP), sin OpenCL en i.MX8M Mini, sin `USE_PRIORITIZED_TEXT_FOR_LD`, sin mimalloc (SIGILL en Cortex-A53), BLAS/LAPACK con OpenBLAS en lugar de Eigen y `-j 8`.
- `python3-polars-runtime-64_%.bbappend`: limita cargo a 4 jobs (OOM con LTO).
- `openblas_%.bbappend`: `PACKAGECONFIG` que necesita SciPy y `-Wno-error=incompatible-pointer-types` (GCC 14+ en sbgemm).
- `ffmpeg_%.bbappend`: deshace los `PACKAGECONFIG` que añade meta-python-ai a ffmpeg.
- `rbz-image-ml.bbappend`: añade `packagegroup-rbz-ml-python`.

## Recursos de build

PyTorch, Polars (Rust con LTO), PySide6 y vulkan-validation-layers usan varios GB por job.
Con los valores por defecto (`BB_NUMBER_THREADS` y `PARALLEL_MAKE` = nº de cores) se puede
agotar la RAM. Para un host de 48 cores y 128 GB, en `local.conf`:

    BB_NUMBER_THREADS = "16"
    PARALLEL_MAKE = "-j 24"
    BB_PRESSURE_MAX_MEMORY = "10000"

## Prueba en la placa

`scripts/rbz-ml-check.sh` comprueba los paquetes instalados (rpm) y ejecuta una prueba funcional de
numpy, scipy, opencv, PySide6 (offscreen), torch, torchvision, ultralytics y TFLite en CPU/NPU:

    scp scripts/rbz-ml-check.sh root@<ip>:/tmp/
    ssh root@<ip> /tmp/rbz-ml-check.sh             # i.MX8MP: incluye la NPU
    ssh root@<ip> /tmp/rbz-ml-check.sh --no-npu    # i.MX8MP Lite, 8MM, 8MN
                                                   # -v para ver toda la salida
