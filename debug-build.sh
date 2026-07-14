#!/bin/sh
git pull
cd build
rm -rf *
#cmake ../ -DCMAKE_BUILD_TYPE=Debug \
#          -DCMAKE_CXX_FLAGS="-fsanitize=address -fno-omit-frame-pointer" \
#          -DCMAKE_LINK_OPTIONS=-fsanitize=address 2>&1 | tee cmake.log
cmake ../ -DCMAKE_BUILD_TYPE=Debug 2>&1 | tee cmake.log
make -j4 VERBOSE=1                 2>&1 | tee make.log
if [ "$(uname)" = "Darwin" ]; then
    make install 2>&1 | tee install.log
else
    sudo make install 2>&1 | tee install.log
    sudo ldconfig
fi
