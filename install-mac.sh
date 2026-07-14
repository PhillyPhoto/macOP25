#!/bin/bash

# macOP25 install script for macOS (Homebrew, Apple Silicon or Intel)
#
# Mirrors what install.sh does for Debian/apt, but:
#  - installs dependencies via Homebrew instead of apt
#  - builds gr-osmosdr from source, since no Homebrew formula exists for it
#  - skips Linux-only steps (kernel module blacklist, udev rules, ldconfig)

set -e

if [ ! -d op25/gr-op25 ]; then
	echo "====== error, op25 top level directories not found"
	echo "====== you must change to the op25 (macOP25) top level directory"
	echo "====== before running this script"
	exit 1
fi
OP25_ROOT="$(pwd)"

# Initialize variables
FORCE=false
BREW_PREFIX_ARG=""

while getopts ":fp:" opt; do
  case $opt in
    f)
      FORCE=true
      ;;
    p)
      BREW_PREFIX_ARG="$OPTARG"
      ;;
    *)
      ;;
  esac
done

# Locate Homebrew. Some Macs have both a native (/opt/homebrew) and a
# Rosetta/x86_64 (/usr/local) install; default to the native one on Apple
# Silicon rather than trusting whatever "brew" resolves to first on PATH.
if [ -n "$BREW_PREFIX_ARG" ]; then
    BREW="$BREW_PREFIX_ARG/bin/brew"
elif [ "$(uname -m)" = "arm64" ] && [ -x /opt/homebrew/bin/brew ]; then
    BREW=/opt/homebrew/bin/brew
elif command -v brew >/dev/null 2>&1; then
    BREW="$(command -v brew)"
else
    echo "====== error, Homebrew not found."
    echo "====== install it from https://brew.sh and re-run this script"
    exit 1
fi
PREFIX="$("$BREW" --prefix)"
echo "Using Homebrew at $PREFIX"

echo "====== Installing Homebrew dependencies"
"$BREW" install gnuradio uhd librtlsdr hackrf cmake pkg-config cppunit \
    spdlog libsndfile orc pybind11 doxygen clang-format gnuplot boost

# Find the python3 that Homebrew's gnuradio is actually built against
PY3="$("$BREW" --prefix gnuradio)/bin/python3"
if [ ! -x "$PY3" ]; then
    PY3="$PREFIX/bin/python3"
fi
if [ ! -x "$PY3" ]; then
    echo "====== error, could not locate a python3 to use; aborting"
    exit 1
fi
echo "Using python3 at $PY3"

echo "====== Installing Python dependencies"
# six is only needed by gr-osmosdr's doxygen->docstring scraper at build time
"$PY3" -m pip install --quiet --break-system-packages numpy waitress requests packaging six \
    || "$PY3" -m pip install --quiet numpy waitress requests packaging six

echo "$PY3" > op25/gr-op25_repeater/apps/op25_python
echo "====== wrote op25_python -> $PY3"

# gr-osmosdr has no Homebrew formula, so build it from source against the
# Homebrew-provided gnuradio/uhd/hackrf/rtl-sdr. The gqrx-sdr fork is used
# because it (unlike the original osmocom tree) is actively kept building
# against recent GNU Radio releases.
GR_OSMOSDR_LIB=$(ls "$PREFIX"/lib/libgnuradio-osmosdr* 2>/dev/null | head -1 || true)
if [ -n "$GR_OSMOSDR_LIB" ] && [ "$FORCE" != true ]; then
    echo "====== gr-osmosdr already installed at $GR_OSMOSDR_LIB, skipping (use -f to force rebuild)"
else
    echo "====== Building gr-osmosdr from source"
    DEPS_DIR="$OP25_ROOT/deps"
    mkdir -p "$DEPS_DIR"
    if [ ! -d "$DEPS_DIR/gr-osmosdr" ]; then
        git clone https://github.com/gqrx-sdr/gr-osmosdr.git "$DEPS_DIR/gr-osmosdr"
        # Homebrew's Boost (1.87+) no longer builds a separate boost_system
        # library (Boost.System became header-only), but gr-osmosdr still
        # asks for it as a required component. Drop it; nothing in the tree
        # actually links against Boost::system.
        sed -i '' 's/find_package(Boost "1.65" REQUIRED chrono thread system)/find_package(Boost "1.65" REQUIRED chrono thread)/' \
            "$DEPS_DIR/gr-osmosdr/CMakeLists.txt"
    fi
    cd "$DEPS_DIR/gr-osmosdr"
    rm -rf build
    mkdir build
    cd build
    cmake .. -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        2>&1 | tee cmake.log
    make -j"$(sysctl -n hw.ncpu)" 2>&1 | tee make.log
    make install 2>&1 | tee install.log
    cd "$OP25_ROOT"
fi

echo "====== Building macOP25"
rm -rf build
mkdir build
cd build
cmake .. -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    2>&1 | tee cmake.log
make -j"$(sysctl -n hw.ncpu)" 2>&1 | tee make.log
make install 2>&1 | tee install.log

echo "====== Done. macOP25 installed against Homebrew prefix $PREFIX"
