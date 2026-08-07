#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

rm -f LightTable.zip
ditto -c -k --sequesterRsrc --keepParent LightTable.app LightTable.zip
ls -lh LightTable.zip
