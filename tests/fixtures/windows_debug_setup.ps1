$ErrorActionPreference = 'Stop'
$env:NATIVE_ROOT = Join-Path $env:RUNNER_TEMP 'Native debug project'
New-Item -Type Directory $env:NATIVE_ROOT | Out-Null
$env:NATIVE_REPO = $pwd.Path
$pin = (Get-Content lazy-lock.json -Raw | ConvertFrom-Json).'nvim-dap'.commit
Set-Location $env:NATIVE_ROOT
git init -q dap
git -C dap fetch -q --depth 1 https://github.com/mfussenegger/nvim-dap.git $pin
if ($LASTEXITCODE) { throw 'Cannot fetch locked nvim-dap' }
git -C dap checkout -q FETCH_HEAD
if ($LASTEXITCODE) { throw 'Cannot check out nvim-dap' }
$archive = 'codelldb.zip'
Invoke-WebRequest https://github.com/vadimcn/codelldb/releases/download/v1.12.3/codelldb-win32-x64.vsix -OutFile $archive
if ((Get-FileHash $archive).Hash -ne 'a916e509308dac817732f63ca604a8b93ed29cd16f38a2fa9f0b64ed58e8f51a') { throw 'CodeLLDB digest mismatch' }
Expand-Archive $archive -DestinationPath mason/packages/codelldb
@('int main() {', '  volatile int marker = 42;', '  return marker - 42;', '}') | Set-Content -Encoding ascii smoke.cpp
$vs = & "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'MSVC unavailable' }
@(
  "@call `"$vs\Common7\Tools\VsDevCmd.bat`" -arch=x64"
  '@if errorlevel 1 exit /b 1'
  '@cl /nologo /Od /Z7 smoke.cpp /link /DEBUG:FULL /PDB:smoke.pdb'
) | Set-Content -Encoding ascii build.cmd
cmd /c build.cmd
if ($LASTEXITCODE -or !(Test-Path smoke.pdb)) { throw 'MSVC/PDB build failed' }
clangd --version
if ($LASTEXITCODE) { throw 'clangd unavailable' }
nvim --headless --noplugin -u NONE -l "$env:NATIVE_REPO/tests/fixtures/windows_debug_lifecycle.lua"
exit $LASTEXITCODE
