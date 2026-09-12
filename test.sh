#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/ModuleCache
case "${1:-}" in
  ""|--gpu) ;;
  *) echo "Usage: ./test.sh [--gpu]" >&2; exit 2 ;;
esac
run_test() {
  local name="$1"
  shift
  swiftc -module-cache-path .build/ModuleCache -parse-as-library "$@" "Tests/$name.swift" -o ".build/$name"
  ".build/$name"
}
run_test EffectAngleTests Sources/EffectAngle.swift
run_test HingeDemoMotionTests Sources/EffectAngle.swift Sources/HingeDemoMotion.swift
run_test DesktopOverlayLayoutTests Sources/DesktopOverlayLayout.swift
run_test PermissionPreparationTests Sources/ScreenCapturePermissionPreparation.swift
if [[ "${1:-}" == --gpu ]]; then
  run_test RendererActivityTests -framework AppKit -framework SwiftUI -framework MetalKit Sources/GlassRenderer.swift
fi
