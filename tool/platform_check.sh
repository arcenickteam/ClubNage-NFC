#!/bin/sh
set -eu
printf '\n=== ClubNage platform check ===\n'
if command -v flutter >/dev/null 2>&1; then
  flutter --version
else
  echo 'Flutter n’est pas installé sur cette machine.'
fi
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version || true
else
  echo 'Xcode n’est pas installé ou xcodebuild n’est pas disponible.'
fi
