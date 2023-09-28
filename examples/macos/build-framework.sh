#!/bin/sh
# build ijk framework.

set -e

if [[ ! -d Pods/IJKMediaPlayerKit.xcodeproj ]]; then
    echo "pod install"
    pod install
fi

# 1
PROJECT_NAME="IJKMediaPlayerKit"
TARGET_NAME="IJKMediaPlayerKit"
WORK_DIR='build'

# 2
if [ -d ${WORK_DIR} ]; then
    rm -rf ${WORK_DIR}
fi

# 3 
# project方式
# xcodebuild -showsdks
# Build the framework for device and simulator with all architectures. 编译真机和模拟器支持的所有架构，如果需要module，加上defines_module=yes
export MACOSX_DEPLOYMENT_TARGET=10.11

xcodebuild -project "Pods/${PROJECT_NAME}.xcodeproj" \
           -target "${TARGET_NAME}"  \
           -configuration Release  \
           -arch arm64 -arch x86_64  \
           only_active_arch=no  \
           -sdk macosx \
           >/dev/null

cd build/Release/${TARGET_NAME}

echo "framework dir: $PWD"