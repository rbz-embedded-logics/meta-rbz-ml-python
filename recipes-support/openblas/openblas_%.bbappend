PACKAGECONFIG = "lapack cblas affinity dynarch"

# GCC 14+: sbgemm passes bfloat16 kernels to gemm_thread_mn (float *)
CFLAGS:append = " -Wno-error=incompatible-pointer-types"
