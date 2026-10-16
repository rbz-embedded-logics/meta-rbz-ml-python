#!/bin/sh
# Check of the ML Python stack on the target

usage() {
    echo "Uso: $0 [--npu | --no-npu] [-v]"
    echo "  --npu     prueba la NPU (por defecto, i.MX8MP)"
    echo "  --no-npu  sin pruebas de NPU (i.MX8MP Lite, i.MX8MM, i.MX8MN)"
    echo "  -v        muestra toda la salida de cada prueba"
    exit 2
}

VERBOSE=0
NPU=1
for arg in "$@"; do
    case "$arg" in
        --npu) NPU=1 ;;
        --no-npu) NPU=0 ;;
        -v) VERBOSE=1 ;;
        *) usage ;;
    esac
done
TIMEOUT=$(command -v timeout >/dev/null && echo "timeout 300")
PASS=0
FAIL=0
SKIP=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run() {
    name=$1; shift
    out=$("$@" 2>&1)
    rc=$?
    if [ $rc -eq 0 ]; then
        PASS=$((PASS + 1)); printf '[ OK ] %-28s %s\n' "$name" "$(echo "$out" | tail -n 1)"
    elif [ $rc -eq 77 ]; then
        SKIP=$((SKIP + 1)); printf '[SKIP] %-28s %s\n' "$name" "$(echo "$out" | tail -n 1)"
    else
        FAIL=$((FAIL + 1)); printf '[FAIL] %-28s rc=%s%s\n' "$name" "$rc" "$([ $rc -gt 128 ] && echo " (signal $((rc - 128)))")"
        echo "$out" | tail -n 15 | sed 's/^/       /'
    fi
    [ $VERBOSE -eq 1 ] && echo "$out" | sed 's/^/       | /'
}

py() { python3 -c "$1"; }

echo "== Paquetes instalados"
for p in python3 python3-pip python3-numpy python3-scipy python3-pyside6 python3-pytorch \
         python3-torchvision python3-ultralytics python3-opencv; do
    run "rpm $p" rpm -q --whatprovides --qf '%{NAME} %{VERSION}\n' "$p"
done

echo "== Python"
run "python3"      py 'import sys; print(sys.version.split()[0])'
run "pip"          python3 -m pip --version
run "venv"         sh -c "python3 -m venv --without-pip --system-site-packages $TMP/venv && $TMP/venv/bin/python -c 'import sys; print(sys.prefix)'"

echo "== Librerias"
run "numpy"        py 'import numpy as np; a=np.random.rand(256,256); assert np.allclose(a@np.linalg.inv(a), np.eye(256), atol=1e-6); print(np.__version__)'
run "scipy"        py 'import scipy, numpy as np; from scipy import linalg, signal, optimize
x=np.linspace(0,1,1000); y=signal.lfilter([1,1],[1],np.sin(x)); r=optimize.minimize(lambda v:(v[0]-3)**2,[0]); assert abs(r.x[0]-3)<1e-4
linalg.lu(np.random.rand(64,64)); print(scipy.__version__)'
run "opencv"       py 'import cv2, numpy as np; img=np.zeros((240,320,3),np.uint8); cv2.rectangle(img,(10,10),(100,100),(0,255,0),-1); assert cv2.cvtColor(img,cv2.COLOR_BGR2GRAY).sum()>0; print(cv2.__version__)'
run "pyside6"      sh -c "QT_QPA_PLATFORM=offscreen python3 -c '
import PySide6
from PySide6.QtCore import qVersion, QTimer
from PySide6.QtWidgets import QApplication, QLabel
app = QApplication([]); w = QLabel(\"rbz\"); w.show()
QTimer.singleShot(100, app.quit); app.exec()
print(\"PySide6\", PySide6.__version__, \"Qt\", qVersion())'"
run "torch"        py 'import torch; a=torch.rand(128,128); b=torch.linalg.inv(a)@a; assert torch.allclose(b,torch.eye(128),atol=1e-3)
m=torch.nn.Sequential(torch.nn.Conv2d(3,8,3),torch.nn.ReLU()); y=m(torch.rand(1,3,64,64)); y.sum().backward()
print(torch.__version__, "threads", torch.get_num_threads())'
run "torchvision"  py 'import torch, torchvision; from torchvision import models, transforms
m=models.mobilenet_v3_small(weights=None).eval(); y=m(torch.rand(1,3,224,224)); assert y.shape==(1,1000)
print(torchvision.__version__)'
run "ultralytics"  sh -c "cd $TMP && YOLO_VERBOSE=False python3 -c '
import numpy as np, ultralytics
from ultralytics import YOLO
m = YOLO(\"yolov8n.yaml\")
r = m.predict(np.zeros((640, 640, 3), np.uint8), verbose=False)
print(ultralytics.__version__, \"predict ok\", len(r))'"

echo "== Runtimes ML ($([ $NPU -eq 1 ] && echo 'con NPU' || echo 'sin NPU'))"
VX=/usr/lib/libvx_delegate.so
BM=$(ls /usr/bin/tensorflow-lite-*/examples/benchmark_model 2>/dev/null | head -n 1)
MODEL=$(ls /usr/bin/tensorflow-lite-*/examples/mobilenet_v1_1.0_224_quant.tflite 2>/dev/null | head -n 1)

run "tflite (python)" sh -c "python3 -c 'import importlib.util as u, sys; sys.exit(0 if u.find_spec(\"tflite_runtime\") else 77)' || { echo 'sin modulo python'; exit 77; }
    python3 -c 'import tflite_runtime, tflite_runtime.interpreter as t, sys
m = [m for m in sys.argv[1:] if m]
i = t.Interpreter(model_path=m[0]) if m else None
i and i.allocate_tensors()
print(tflite_runtime.__version__, \"interpreter ok\" if i else \"\")' $MODEL"
run "onnxruntime"  sh -c "python3 -c 'import onnxruntime as o; print(o.__version__, o.get_available_providers())' 2>/dev/null || { echo 'sin modulo python'; exit 77; }"

if [ -n "$BM" ] && [ -n "$MODEL" ]; then
    run "tflite CPU" sh -c "$TIMEOUT $BM --graph=$MODEL --num_runs=20 > $TMP/cpu.log 2>&1; v=\$(grep -o 'Inference (avg): [0-9.e+]*' $TMP/cpu.log | tail -n 1); [ -n \"\$v\" ] && echo \"\$v us\""
else
    run "tflite CPU" sh -c "echo 'benchmark_model o modelo no encontrado'; exit 1"
fi

if [ $NPU -eq 1 ]; then
    run "npu /dev/galcore"   sh -c "[ -e /dev/galcore ] && echo /dev/galcore"
    run "npu vx delegate"    sh -c "ls $VX"
    run "npu onnxruntime EP" sh -c "python3 -c 'import onnxruntime as o; p=o.get_available_providers(); print(p); assert \"VSINPUExecutionProvider\" in p' 2>&1 || exit 1"
    if [ -n "$BM" ] && [ -n "$MODEL" ] && [ -e "$VX" ]; then
        # The VX delegate falls back to CPU without NPU: require delegated nodes and a faster run
        run "tflite NPU" sh -c "$TIMEOUT $BM --graph=$MODEL --num_runs=20 --external_delegate_path=$VX > $TMP/npu.log 2>&1
            grep -m1 -E 'Replacing .* node\(s\) with delegate|graph will be completely executed by the delegate' $TMP/npu.log || { tail -n 20 $TMP/npu.log; exit 1; }
            npu=\$(grep -o 'Inference (avg): [0-9.e+]*' $TMP/npu.log | tail -n 1 | awk '{print int(\$3)}')
            cpu=\$(grep -o 'Inference (avg): [0-9.e+]*' $TMP/cpu.log | tail -n 1 | awk '{print int(\$3)}')
            [ -n \"\$npu\" ] || { tail -n 20 $TMP/npu.log; exit 1; }
            echo \"NPU \$npu us / CPU \${cpu:-?} us\"
            [ -z \"\$cpu\" ] || [ \$npu -lt \$cpu ]"
    else
        run "tflite NPU" sh -c "echo 'benchmark_model, modelo o $VX no encontrado'; exit 1"
    fi
fi

echo
echo "Resultado: $PASS OK, $FAIL FAIL, $SKIP SKIP"
[ $FAIL -eq 0 ]
