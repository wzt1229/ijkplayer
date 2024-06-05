#! /usr/bin/env bash
#
# Copyright (C) 2022 Matt Reach<qianlongxu@gmail.com>

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
# ./install-pre-any.sh all
# ./install-pre-any.sh ios 'openssl opus bluray dav1d'
# ./install-pre-any.sh tvos 'openssl'
# ./install-pre-any.sh macos 'openssl ffmpeg'

#----------------------------------------------------------
# 当发布新版本库时，修改对应的 TAG 值
#----------------------------------------------------------
OPUS_TAG='opus-1.4-240605102127'
MAC_BLURAY_TAG='bluray-1.3.4-240605103055'
DAV1D_TAG='dav1d-1.3.0-240605103034'
OPENSSL_TAG='openssl-1.1.1w-240605103006'
DVDREAD_TAG='dvdread-6.1.3-240605103023'
FREETYPE_TAG='freetype-2.13.2-240605105138'
UNIBREAK_TAG='unibreak-5.1-240604145913'
FRIBIDI_TAG='fribidi-1.0.13-240605105200'
HARFBUZZ_TAG='harfbuzz-8.3.0-240605110352'
ASS_TAG='ass-0.17.1-240605112231'
FFMPEG_TAG='ffmpeg-5.1.4-240605162418'
#----------------------------------------------------------

set -e

PLAT=`echo $1 | tr '[:upper:]' '[:lower:]'`
_LIBS=$2

THIS_DIR=$(DIRNAME=$(dirname "$0"); cd "$DIRNAME"; pwd)
cd "$THIS_DIR"

function install_lib ()
{
    local plat=$1
    ./tools/install-pre-lib.sh "$plat" "$TAG"
}

function usage() {
    echo "=== useage ===================="
    echo "Download pre-compiled libs from github:"
    echo " $0 [ios,macos,all] [all|openssl|opus|bluray|dav1d|dvdreader|freetype|fribidi|harfbuzz|unibreak|ass|ffmpeg]"
    exit 1
}

function download_palt() {
    
    if [[ -z "$_LIBS" || "$_LIBS" == "all" ]]; then
        LIBS=$(cat apple/compile-cfgs/list_${PLAT}.txt)
    else
        LIBS="$_LIBS"
    fi

    for lib in $LIBS
    do
        echo "===[install pre-compile $lib for $PLAT]===================="
        TAG=
        case $lib in
            'ffmpeg')
                TAG=$FFMPEG_TAG
            ;;
            'libyuv')
                TAG=$LIBYUV_TAG
            ;;
            'openssl')
                TAG=$OPENSSL_TAG
            ;;
            'opus')
                TAG=$OPUS_TAG
            ;;
            'bluray')
                TAG=$MAC_BLURAY_TAG
            ;;
            'dav1d')
                TAG=$DAV1D_TAG
            ;;
            'dvdread')
                TAG=$DVDREAD_TAG
            ;;
            'freetype')
                TAG=$FREETYPE_TAG
            ;;
            'harfbuzz')
                TAG=$HARFBUZZ_TAG
            ;;
            'fribidi')
                TAG=$FRIBIDI_TAG
            ;;
            'unibreak')
                TAG=$UNIBREAK_TAG
            ;;
            'ass')
                TAG=$ASS_TAG
            ;;
            *)
                echo "wrong lib name:$lib"
                usage
            ;;
        esac
        
        if [[ -z "$TAG" ]]; then
            echo "== $lib tag is empty,just skip it."
        else
            echo "== $PLAT $lib -> $TAG"
            install_lib $PLAT
        fi
        echo "===================================="
    done
}

case "$PLAT" in
    'ios' | 'macos' | 'tvos')
        download_palt
    ;;
    'all')
        p="ios macos tvos"
        for plat in $p
        do
            PLAT=$plat
            download_palt
        done
    ;;
    *)
        usage
    ;;
esac