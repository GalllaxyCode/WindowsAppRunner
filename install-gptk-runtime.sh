#!/bin/zsh
# Installs the D3DMetal graphics layer from one of Apple's Game Porting Toolkit disk images as an
# extra runtime for Windows App Runner.
#
#   ./install-gptk-runtime.sh [--experimental] [--base <wine dir>] ~/Downloads/Game_Porting_Toolkit_4.0_beta_3.dmg
#
# Accepts the full toolkit DMG or the inner "Evaluation environment for Windows games" DMG.
# --base picks the Wine to build on (default: the Homebrew Game Porting Toolkit's), for example a
# CrossOver-source Wine from build-crossover-wine.sh. Apple's libraries are compiled against a
# particular Wine, so the install is refused when the base Wine lacks a Windows function they
# import, or lacks CrossOver's winemac.drv bridge (macdrv_functions) that D3DMetal draws through.
# --experimental marks the runtime so Windows App Runner only offers it when experimental runtimes
# are switched on, and runs it in its own Windows environment.
# The Homebrew Game Porting Toolkit.app is never modified: its Wine is cloned (APFS copy-on-write,
# so the copy uses almost no disk space) and Apple's libraries are merged on top of the clone.
# (Apple's Read Me says to move lib/wine aside first, but in this Wine build that folder holds all
# of Wine, not just the graphics libraries, so the files are merged in instead.)
set -euo pipefail

BASE="/Applications/Game Porting Toolkit.app/Contents/Resources/wine"
experimental=0
while [[ ${1-} == --* ]]; do
  case $1 in
    --base) BASE=${2:?--base needs a Wine directory}; shift 2 ;;
    --experimental) experimental=1; shift ;;
    *) print -u2 "unknown option $1"; exit 1 ;;
  esac
done
dmg=${1:?usage: $0 [--experimental] [--base <wine dir>] <Game Porting Toolkit .dmg>}
RUNTIMES="$HOME/Library/Application Support/Windows App Runner/Runtimes"

# Wine 9+ has a single "wine" loader; older builds have "wine64".
loader=$BASE/bin/wine64
[[ -x $loader ]] || loader=$BASE/bin/wine
[[ -x $loader ]] || { print -u2 "No Wine found at $BASE. Install the base first: brew install --cask gcenx/wine/game-porting-toolkit"; exit 1 }
base_version=$("$loader" --version 2>/dev/null || print "Wine at $BASE")

work=$(mktemp -d)
cleanup() {
  for m in "$work"/eval "$work"/outer; do [[ -d $m ]] && hdiutil detach -quiet "$m" 2>/dev/null || true; done
  rm -rf "$work"
}
trap cleanup EXIT

attach() { mkdir -p "$2"; hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$2" "$1" >/dev/null 2>&1 }

# Prints "dll function" for every import of the DLLs in $1 that the Wine DLLs in $2 don't export.
missing_imports() {
  local redist=$1 base=$2 lib fn
  typeset -A exports
  for dll in "$redist"/*.dll; do
    xcrun llvm-objdump -p "$dll" | awk '
      /DLL Name:/      { lib = tolower($3); inimp = 0; next }
      /Hint\/Ord/      { inimp = (lib != ""); next }
      /^[[:space:]]*$/ { inimp = 0; next }
      inimp && $1 ~ /^[0-9]+$/ && NF >= 2 { print lib, $2 }'
  done | sort -u | while read -r lib fn; do
    [[ -f $redist/$lib || ! -f $base/$lib ]] && continue
    if [[ -z ${exports[$lib]-} ]]; then
      # Forwarded exports have no RVA column, so the name is $2 instead of $3.
      exports[$lib]=" $(xcrun llvm-objdump -p "$base/$lib" | awk '/^Export Table:/ {e = 1; next}
        e && $1 ~ /^[0-9]+$/ && NF >= 2 {print ($2 ~ /^0x/ ? $3 : $2)}' | tr '\n' ' ') "
    fi
    [[ ${exports[$lib]} == *" $fn "* ]] || print "  $lib → $fn"
  done
}

attach "$dmg" "$work/outer"
inner=( "$work"/outer/Evaluation\ environment\ for\ Windows\ games*.dmg(N) )
if (( $#inner )); then
  attach "$inner[1]" "$work/eval"
  src="$work/eval"; label=${inner[1]:t:r}
else
  src="$work/outer"; label=${dmg:t:r}
fi
version=${${label#Evaluation environment for Windows games }//_/ }
version=${version#Game Porting Toolkit }
redist="$src/redist/lib"

[[ -d $redist/external/D3DMetal.framework ]] || { print -u2 "No D3DMetal found in $dmg"; exit 1 }
codesign --verify --deep --strict "$redist/external/D3DMetal.framework"
# Capture first: piping into grep -q would SIGPIPE codesign and trip pipefail.
signature=$(codesign -dv --verbose=2 "$redist/external/D3DMetal.framework" 2>&1)
[[ $signature == *"Authority=Apple Root CA"* ]] \
  || { print -u2 "D3DMetal in this image isn't signed by Apple; refusing to install it."; exit 1 }

missing=$(missing_imports "$redist/wine/x86_64-windows" "$BASE/lib/wine/x86_64-windows")
if [[ -n $missing ]]; then
  print -u2 "✗ GPTK $version needs a newer Wine than $base_version."
  print -u2 "  Its graphics libraries call Windows functions this Wine doesn't provide:"
  print -u2 "$missing"
  print -u2 "  Games would fail to start (\"dxgi.dll failed to initialize\"). Nothing was installed."
  exit 2
fi

# D3DMetal finds each game window through CrossOver's winemac.drv export table (upstream Wine has
# no equivalent; D3DMetal logs "No macdrv window data for hwnd").
winemac=( "$BASE"/lib/wine/x86_64-unix/winemac.drv.so(N) "$BASE"/lib/wine/x86_64-unix/winemac.so(N) )
if (( ! $#winemac )) || ! nm -gU "$winemac[1]" 2>/dev/null | grep -q " _macdrv_functions$"; then
  print -u2 "✗ $base_version has no D3DMetal window bridge (winemac.drv macdrv_functions)."
  print -u2 "  D3DMetal needs a Wine built from CrossOver sources. Nothing was installed."
  exit 2
fi

dest="$RUNTIMES/GPTK $version"
print "→ Installing GPTK $version"
rm -rf "$dest.partial"
mkdir -p "$dest.partial"
cp -cR "$BASE" "$dest.partial/wine"
ditto "$redist" "$dest.partial/wine/lib"

# Enable Apple's DLSS → MetalFX bridge (Read Me: "Prepare your environment").
w="$dest.partial/wine/lib/wine"
cp -fP "$w/x86_64-unix/nvngx-on-metalfx.so" "$w/x86_64-unix/nvngx.so"
cp -f "$w/x86_64-windows/nvngx-on-metalfx.dll" "$w/x86_64-windows/nvngx.dll"

print "$version" > "$dest.partial/VERSION"
print "$base_version" > "$dest.partial/BASE"
(( experimental )) && : > "$dest.partial/EXPERIMENTAL"
rm -rf "$dest"
mv "$dest.partial" "$dest"
print "✓ Installed to $dest"
