#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
python3 scripts/fetch.py
python3 tests/make_fixtures.py
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release "$@"
cmake --build build -j 4
ctest --test-dir build --output-on-failure
python3 scripts/sign.py 'build/Wai Browser.app' --identity "${WAI_SIGN_IDENTITY:-79F4FFC61B54D0E56B37B4D0643C331F73C3BDC2}"
