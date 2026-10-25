#!/bin/bash
set -euo pipefail

test -f project.yml && test -f Package.swift
python3 scripts/fixtures/prepare_native_summary.py --framework-only

mkdir -p .agent-local/tools
curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 --max-time 120 \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
  -o .agent-local/tools/xcodegen.zip
printf '%s  %s\n' '4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806' '.agent-local/tools/xcodegen.zip' | shasum -a 256 -c -
unzip -q -o .agent-local/tools/xcodegen.zip -d .agent-local/tools
.agent-local/tools/xcodegen/bin/xcodegen generate --spec project.yml
