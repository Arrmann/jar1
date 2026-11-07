# Downloads an optional hand-landmark ONNX model into this folder.
# Classical CV works without it. ONNX needs: cargo build -p jarvis-gestures --features onnx

$ErrorActionPreference = "Stop"
$dest = Join-Path $PSScriptRoot "hand_landmark.onnx"

if (Test-Path $dest) {
    Write-Host "Already present: $dest"
    exit 0
}

# Placeholder note: place a compatible hand_landmark.onnx here manually.
# We do not auto-download a large binary into the repo by default.
Write-Host "No automatic download configured."
Write-Host "Place hand_landmark.onnx next to this script, then rebuild with --features onnx."
Write-Host "Without the model, jarvis-gestures uses classical CV (default)."
exit 0
