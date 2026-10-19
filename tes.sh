#!/bin/bash

rm -rf .repo/local_manifests/

# repo init 
repo init -u https://github.com/crdroidandroid/android.git -b 16.0 --git-lfs --no-clone-bundle --depth=1
echo "=================="
echo "Repo init success"
echo "=================="

# clone tree
git clone -b lineage-23.2-dynamic https://github.com/pix106/android_device_xiaomi_lavender.git device/xiaomi/lavender
git clone -b 16.2-dynamic https://github.com/pix106/android_device_xiaomi_sdm660-common.git device/xiaomi/sdm660-common
git clone -b 16.2 https://github.com/pix106/android_vendor_xiaomi_lavender.git vendor/xiaomi/lavender
git clone -b 16.2 https://github.com/pix106/android_vendor_xiaomi_sdm660-common.git vendor/xiaomi/sdm660-common
git clone -b old/main-dynamic https://github.com/pix106/android_kernel_xiaomi_sdm660_southwest-ng.git kernel/xiaomi/sdm660
git clone https://github.com/pix106/android_hardware_qcom-caf_camera.git hardware/qcom-caf/sdm660/camera
git clone -b android-16 https://github.com/Amritorock/hardware_xiaomi.git hardware/xiaomi
echo "============================"
echo "clone dt successful"
echo "============================"

# Build Sync
/opt/crave/resync.sh 
echo "============="
echo "Sync success"
echo "============="

# Set up build environment
source build/envsetup.sh
echo "============="

# Build
lunch lineage_lavender-bp4a-user
m bacon
