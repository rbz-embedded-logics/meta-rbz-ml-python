# i.MX GPU BSPs provide virtual/mesa through mesa-gl, there is no mesa recipe
DEPENDS:remove:class-target = "mesa"
DEPENDS:append:class-target = " virtual/mesa"

# i.MX8M Mini GPU has no OpenCL
DEPENDS:remove:mx8mm-nxp-bsp = "opencl-headers virtual/libopencl1"
EXTRA_OECMAKE:append:mx8mm-nxp-bsp = " -DUSE_OPENCL=OFF"

# Each compile job can take several GB of RAM
PARALLEL_MAKE = "-j 16"

# NXP pins glslang to 1.3.275 (Vulkan 1.3), shaderc 2026.1 needs Vulkan 1.4
DEPENDS:remove:class-target = "shaderc vulkan-headers vulkan-loader"
RDEPENDS:${PN}:remove:class-target = "shaderc vulkan-loader"
EXTRA_OECMAKE:append:class-target = " -DUSE_VULKAN=OFF -DUSE_VULKAN_FP16_INFERENCE=OFF \
    -DUSE_VULKAN_RELAXED_PRECISION=OFF -DUSE_VULKAN_SHADERC_RUNTIME=OFF"

# generate_linker_script.py runs ${LD} as a single executable, it fails with Yocto's LD
EXTRA_OECMAKE:append:class-target = " -DUSE_PRIORITIZED_TEXT_FOR_LD=OFF"
export USE_PRIORITIZED_TEXT_FOR_LD = "0"

# mimalloc (linked into libc10) is built with -march=armv8.1-a (LSE atomics), SIGILL on Cortex-A53.
# CMakeLists.txt forces USE_MIMALLOC ON for aarch64, so -DUSE_MIMALLOC=OFF is not enough
do_configure:prepend() {
    sed -i 's/^  set(USE_MIMALLOC ON)$/  set(USE_MIMALLOC OFF)/' ${S}/CMakeLists.txt
}
EXTRA_OECMAKE:append:class-target = " -DUSE_MIMALLOC=OFF"

# Eigen has no LAPACK (torch.linalg fails), use OpenBLAS built with LAPACK
DEPENDS:append:class-target = " openblas"
EXTRA_OECMAKE_ARCH_FLAGS:class-target:aarch64 = "-DBLAS=OpenBLAS -DUSE_LAPACK=ON"
