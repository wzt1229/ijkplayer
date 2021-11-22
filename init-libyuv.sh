#! /usr/bin/env bash
#
# Copyright (C) 2013-2015 Bilibili
# Copyright (C) 2013-2015 Zhang Rui <bbcallen@gmail.com>
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

IJK_LIBYUV_UPSTREAM=https://github.com/lemenkov/libyuv.git
IJK_LIBYUV_FORK=https://github.com/lemenkov/libyuv.git
IJK_LIBYUV_COMMIT=master
IJK_LIBYUV_LOCAL_REPO=extra/libyuv
TARGET="$1"

if [ "$IJK_LIBYUV_REPO_URL" != "" ]; then
    IJK_LIBYUV_UPSTREAM=$IJK_LIBYUV_REPO_URL
    IJK_LIBYUV_FORK=$IJK_LIBYUV_REPO_URL
fi

set -e
TOOLS=tools

function pull_base()
{
    echo "== pull libyuv base =="
    sh $TOOLS/pull-repo-base.sh $IJK_LIBYUV_UPSTREAM $IJK_LIBYUV_LOCAL_REPO
}

function pull_fork()
{
    echo "== pull libyuv fork $2 $1 =="
    dir="$2/libyuv-$1"
    sh $TOOLS/pull-repo-ref.sh $IJK_LIBYUV_FORK $dir ${IJK_LIBYUV_LOCAL_REPO}
    cd $dir
    git checkout ${IJK_LIBYUV_COMMIT} -B ijkplayer
    cd -
}

function main()
{
    if [ "$TARGET" = 'ios' ];then
        pull_base
        pull_fork "arm64" "$TARGET"
        pull_fork "x86_64" "$TARGET"
    elif [ "$TARGET" = 'mac' ];then
        pull_base
        pull_fork "x86_64" "$TARGET"
    else
        echo "Usage:"
        echo "  ./init-libyuv.sh ios"
        echo "  ./init-libyuv.sh mac"
        exit 1
    fi
}

main
