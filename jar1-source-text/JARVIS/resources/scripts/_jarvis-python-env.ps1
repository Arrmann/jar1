# Shared env for bundled embeddable Python (Silero). ASCII-only.
# Stops a system PYTHONPATH / user-site from hijacking torch (CUDA leftover, etc.).

function Clear-JarvisPythonEnv {
  $env:PYTHONHOME = $null
  $env:PYTHONPATH = $null
  $env:PYTHONUSERBASE = $null
  $env:PYTHONNOUSERSITE = "1"
  $env:PIP_USER = "0"
  $env:PIP_DISABLE_PIP_VERSION_CHECK = "1"
  $env:PIP_DEFAULT_TIMEOUT = "600"
}

function Apply-JarvisPythonRuntime([string]$PyDir) {
  Clear-JarvisPythonEnv
  if ([string]::IsNullOrWhiteSpace($PyDir)) { return }
  if (-not (Test-Path -LiteralPath $PyDir)) { return }
  $scripts = Join-Path $PyDir "Scripts"
  $libBin = Join-Path $PyDir "Library\bin"
  $env:PATH = ($PyDir + ";" + $scripts + ";" + $libBin + ";" + $env:PATH)
}

function Test-JarvisTorchTree([string]$PyDir) {
  if ([string]::IsNullOrWhiteSpace($PyDir)) { return $false }
  $torch = Join-Path $PyDir "Lib\site-packages\torch"
  $init = Join-Path $torch "__init__.py"
  if (-not (Test-Path -LiteralPath $init)) { return $false }
  # CPU wheels often leave c10_cuda.dll on disk. Treat as ready if the CPU runtime exists.
  if (Test-Path -LiteralPath (Join-Path $torch "lib\c10.dll")) { return $true }
  $c = @(Get-ChildItem -LiteralPath $torch -Filter "_C*.pyd" -ErrorAction SilentlyContinue)
  return ($c.Count -gt 0)
}
