# polars-ops/polars-plan need several GB of RAM per rustc job (LTO)
export CARGO_BUILD_JOBS = "4"
