#!/bin/zsh
# Builds Wine from CodeWeavers' published CrossOver sources, for use as a newer base for Apple's
# D3DMetal (GPTK 4.0+), which needs both Wine >= 11's gdi32 D3DKMT functions and CrossOver's
# winemac.drv D3DMetal bridge (macdrv_functions).
#
#   ./build-crossover-wine.sh [version]      # default 26.2.0
#
# Output: ~/Developer/wine-cx-build/<version>/dist/wine  (pass it to install-gptk-runtime.sh --base)
#
# Builds x86_64 macOS code (run under Rosetta, like every Wine for macOS) plus i386/x86_64 Windows
# DLLs with MinGW. Third-party x86_64 libraries (FreeType, GnuTLS, SDL2) are borrowed from the
# Homebrew Game Porting Toolkit.app instead of being rebuilt; their headers come from Homebrew.
#
# Needs: brew install mingw-w64 bison flex freetype gnutls sdl2
set -euo pipefail

version=${1:-26.2.0}
root="$HOME/Developer/wine-cx-build/$version"
deps_src="/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib"
hb=/opt/homebrew

mkdir -p "$root"
cd "$root"

if [[ ! -d sources/wine ]]; then
  print "→ Downloading CrossOver $version sources"
  curl -fL -A "Mozilla/5.0" -o src.tar.gz "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$version.tar.gz"
  tar -xzf src.tar.gz sources/wine
  rm src.tar.gz
fi

# x86_64 copies of the libraries Wine links against at build time and dlopens at run time. The
# whole set is copied because they load each other via @loader_path (FreeType needs libpng, ...).
mkdir -p deps
for lib in "$deps_src"/*.dylib; do
  [[ -e deps/${lib:t} ]] || cp -cP "$lib" deps/
done

# The Command Line Tools are arm64-only (they can't run under Rosetta), so the compiler runs natively
# and targets x86_64. Declaring the build machine x86_64 too keeps it a "native" build: Wine's own
# tools (winebuild, widl, ...) are compiled for x86_64 and run under Rosetta during the build.
export PATH="$hb/opt/bison/bin:$hb/opt/flex/bin:$hb/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MACOSX_DEPLOYMENT_TARGET=14.0
jobs=$(sysctl -n hw.ncpu)

mkdir -p build
cd build
if [[ ! -f Makefile ]]; then
  print "→ Configuring"
  ../sources/wine/configure \
    --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
    --prefix="$root/dist/wine" \
    --enable-archs=i386,x86_64 \
    --disable-tests \
    --without-x --without-wayland --without-gstreamer \
    --without-oss --without-alsa --without-pulse --without-capi --without-gphoto --without-sane \
    CC="clang -arch x86_64" OBJC="clang -arch x86_64" \
    FREETYPE_CFLAGS="-I$hb/include/freetype2" FREETYPE_LIBS="-L$root/deps -lfreetype" \
    GNUTLS_CFLAGS="-I$hb/include" GNUTLS_LIBS="-L$root/deps -lgnutls" \
    SDL2_CFLAGS="-I$hb/include/SDL2 -D_THREAD_SAFE" SDL2_LIBS="-L$root/deps -lSDL2" \
    | tee configure.out | tail -25
fi

# The borrowed libraries have bare install names ("libfreetype.dylib"), which configure's otool
# parsing turns into SONAMEs like "\tlibfreetype.dylib (compatibility version ...)". Wine dlopens
# these names at run time, so reduce them to the plain file name.
sed -E -i '' 's/^(#define SONAME_[A-Z0-9_]+ ")[[:space:]]*([^ "]+)[^"]*"/\1\2"/' include/config.h
# CrossOver's win32u always references SONAME_LIBVULKAN (CodeWeavers build with MoltenVK). Without
# MoltenVK, Wine just logs that the library can't be loaded; D3DMetal doesn't use Vulkan.
sed -i '' 's|^/\* #undef SONAME_LIBVULKAN \*/$|#define SONAME_LIBVULKAN "libvulkan.1.dylib"|' include/config.h
grep -E '^#define SONAME_LIB(FREETYPE|GNUTLS|SDL2) ' include/config.h

# sfnt2fon (generates Wine's bitmap fonts during the build) links FreeType directly; the borrowed
# library's bare install name can't be found from the build tree, so point it at the copy in deps.
make -j$jobs tools/sfnt2fon/sfnt2fon
install_name_tool -change libfreetype.dylib "$root/deps/libfreetype.6.dylib" tools/sfnt2fon/sfnt2fon 2>/dev/null
codesign -f -s - tools/sfnt2fon/sfnt2fon 2>/dev/null

print "→ Building (this takes a while)"
make -j$jobs
make install

# Ship the borrowed libraries with the build so it is self-contained. GnuTLS loads its own
# dependencies via @loader_path, so the whole set goes in, side by side.
for lib in "$deps_src"/*.dylib; do cp -cP "$lib" "$root/dist/wine/lib/"; done
print "✓ Built $("$root/dist/wine/bin/wine" --version 2>/dev/null || print Wine) in $root/dist/wine"
