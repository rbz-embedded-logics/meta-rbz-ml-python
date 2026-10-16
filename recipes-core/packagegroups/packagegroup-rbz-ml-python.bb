SUMMARY = "RBZ Python ML stack: PySide6, SciPy, PyTorch and Ultralytics"
LICENSE = "MIT"

PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit packagegroup

RDEPENDS:${PN} = " \
    python3-pyside6 \
    python3-shiboken6 \
    python3-scipy \
    python3-pytorch \
    python3-torchvision \
    python3-ultralytics \
"
