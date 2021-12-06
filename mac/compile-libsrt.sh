#! /usr/bin/env bash
#
# Copyright (C) 2013-2014 Bilibili
# Copyright (C) 2013-2014 Zhang Rui <bbcallen@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#----------
# modify for your build tool

FF_ALL_ARCHS="x86_64"

#----------
UNI_BUILD_ROOT=`pwd`
UNI_TMP="$UNI_BUILD_ROOT/tmp"
UNI_TMP_LLVM_VER_FILE="$UNI_TMP/llvm.ver.txt"
FF_TARGET=$1
set -e

#----------
FF_LIBS="libsrt"

#----------

install_depends () {
    local name="$1"
    echo "checking ${name}"
    local r=$(brew list | grep "$name")
    if [[ $r != '' ]]; then
        echo "[✅] ${name} is right."
    else
        echo "will use brew install ${name}."
        brew install "$name"
    fi
}

resolve_depends () {
    echo "===================="
    echo "FF_ALL_ARCHS = $FF_ALL_ARCHS"
    echo "[*] check depends ..."
    install_depends 'autoconf'
    install_depends 'automake'
    install_depends 'libtool'
    install_depends 'pkg-config'
    echo "===================="
}

do_lipo () {
    LIB_FILE=$1
    LIPO_FLAGS=
    for ARCH in $FF_ALL_ARCHS
    do
        LIPO_FLAGS="$LIPO_FLAGS $UNI_BUILD_ROOT/build/libsrt-$ARCH/output/lib/$LIB_FILE"
    done

    xcrun lipo -create $LIPO_FLAGS -output $UNI_BUILD_ROOT/build/universal/lib/$LIB_FILE
    xcrun lipo -info $UNI_BUILD_ROOT/build/universal/lib/$LIB_FILE
}

do_lipo_all () {
    mkdir -p $UNI_BUILD_ROOT/build/universal/lib
    echo "lipo archs: $FF_ALL_ARCHS"
    for FF_LIB in $FF_LIBS
    do
        do_lipo "$FF_LIB.a";
    done

    cp -R $UNI_BUILD_ROOT/build/libsrt-x86_64/output/include $UNI_BUILD_ROOT/build/universal/
}

usage () {
    echo "Usage:"
    echo "  compile-libsrt.sh x86_64"
    echo "  compile-libsrt.sh lipo"
    echo "  compile-libsrt.sh all"
    echo "  compile-libsrt.sh clean"
    echo "  compile-libsrt.sh check"
    exit 1
}

#----------
case "$FF_TARGET" in
    'x86_64')
        resolve_depends
        sh tools/do-compile-libsrt.sh $FF_TARGET
    ;;
    'lipo')
        do_lipo_all
    ;;
    'all')
        resolve_depends
        for ARCH in $FF_ALL_ARCHS
        do
            sh tools/do-compile-libsrt.sh $ARCH
        done

        do_lipo_all
    ;;
    'check')
        resolve_depends
    ;;
    'clean')
        for ARCH in $FF_ALL_ARCHS
        do
            cd libsrt-$ARCH && git clean -xdf && cd -
        done
    ;;
    *)
        usage
    ;;
esac
