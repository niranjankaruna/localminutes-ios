#!/bin/bash
set -euo pipefail

native_arguments=(--framework-only --with-simulator)
if [[ $# -gt 0 ]]; then
  if [[ $# -eq 1 && "$1" == "--device-only" ]]; then
    native_arguments=(--framework-only)
  else
    printf '%s\n' 'Usage: bash scripts/prepare-ios.sh [--device-only]' >&2
    exit 2
  fi
fi

test -f project.yml && test -f Package.swift
python3 scripts/fixtures/prepare_native_summary.py "${native_arguments[@]}"

mkdir -p .agent-local/tools
curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 --max-time 120 \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
  -o .agent-local/tools/xcodegen.zip
printf '%s  %s\n' '4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806' '.agent-local/tools/xcodegen.zip' | shasum -a 256 -c -
unzip -q -o .agent-local/tools/xcodegen.zip -d .agent-local/tools
.agent-local/tools/xcodegen/bin/xcodegen generate --spec project.yml
