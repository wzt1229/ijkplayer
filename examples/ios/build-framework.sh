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
OUTPUT_ROOT='Release-ios'
DEVICE_DIR=${WORK_DIR}/'Release-iphoneos'/${TARGET_NAME}/${TARGET_NAME}'.framework'
SIMULATOR_DIR=${WORK_DIR}/'Release-iphonesimulator'/${TARGET_NAME}/${TARGET_NAME}'.framework'
OUTPUT_DIR=${WORK_DIR}/${OUTPUT_ROOT}
OUTPUT_FMK_DIR=${OUTPUT_DIR}/${TARGET_NAME}.framework

# 2
if [ -d ${WORK_DIR} ]; then
    rm -rf ${WORK_DIR}
fi
# 3 
# project方式
# xcodebuild -showsdks
# Build the framework for device and simulator with all architectures. 编译真机和模拟器支持的所有架构，如果需要module，加上defines_module=yes
export IPHONEOS_DEPLOYMENT_TARGET=11.0

xcodebuild -project "Pods/${PROJECT_NAME}.xcodeproj" \
           -target "${TARGET_NAME}"  \
           -configuration Release  \
           -arch arm64  \
           only_active_arch=no  \
           -sdk iphoneos \
           >/dev/null

xcodebuild -project "Pods/${PROJECT_NAME}.xcodeproj" \
           -target "${TARGET_NAME}"  \
           -configuration Release  \
           -arch x86_64  \
           only_active_arch=no  \
           -sdk iphonesimulator \
           >/dev/null

# 4
if [ -d ${OUTPUT_FMK_DIR} ]; then
 rm -rf ${OUTPUT_FMK_DIR}
fi

# 5
# Create the output file including the folders. 创建目标文件，以及其中包含的文件夹
mkdir -p ${OUTPUT_FMK_DIR}
 
# 6
# Copy the device version of framework to destination. 先拷贝真机framework到目标文件
cp -pPR ${DEVICE_DIR}/ ${OUTPUT_FMK_DIR}/

# 7
# Replace the framework executable within the output file framework with
# a new version created by merging the device and simulator
# frameworks' executables with lipo. 合并真机和模拟器 .framework 里面的可执行文件FRAMEWORK_NAME 到目标文件.framework 下
lipo -create -output ${OUTPUT_FMK_DIR}/${TARGET_NAME} ${DEVICE_DIR}/${TARGET_NAME} ${SIMULATOR_DIR}/${TARGET_NAME}
 
# 8
# Copy dSYM files

cp -pPR ${DEVICE_DIR}.dSYM ${OUTPUT_DIR}
cp -pPR ${SIMULATOR_DIR}.dSYM ${OUTPUT_DIR}/${TARGET_NAME}'-simulator.framework.dSYM'

cd ${OUTPUT_DIR}
echo "framework dir: $PWD"