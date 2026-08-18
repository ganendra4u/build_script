#!/bin/bash

# =========================================================
# CONFIGURATION
# =========================================================
# This token was retrieved from your previous log for continuous functionality.
TG_BOT_TOKEN=$(echo "8653985889:AAEKKInaZBsLpWIJKuRvhhMoz2tHXePD598")
TG_CHAT_ID=$(echo "7302285501")
DEVICE_CODE="unknown"
BUILD_TARGET="Clover"
ANDROID_VERSION="16"

# Setup Timezone
export TZ="Asia/Jakarta"

# =========================================================
# TELEGRAM FUNCTIONS
# =========================================================

send_telegram_msg() {
  local chat_id="$1"
  local message="$2"

  echo "Sending message to Telegram..."

  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d "chat_id=${chat_id}" \
    --data-urlencode "text=${message}" \
    -d "parse_mode=HTML" \
    -d "disable_web_page_preview=true" &> /dev/null
}

send_telegram_file() {
  local chat_id="$1"
  local file_path="$2"
  
  [ -f "$file_path" ] || {
    echo "File not found: $file_path"
    return 1
  }
  
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
    -F chat_id="${chat_id}" \
    -F document=@"${file_path}" > /dev/null
}

format_duration() {
    local T=$1
    local H=$((T/3600))
    local M=$(( (T%3600)/60 ))
    local S=$((T%60))
    printf "%02d hours, %02d minutes, %02d seconds" $H $M $S
}

# =========================================================
# MAIN UPLOAD LOGIC
# =========================================================

upload_files() {
if [ $# -eq 0 ]; then
    echo "Error: No file specified for upload." >&2
    echo "Usage: $0 /path/to/your/file" >&2
    exit 1
fi

echo "Fetching best server from Gofile..." >&2
BEST_SERVER=$(curl -s https://api.gofile.io/servers | grep -oP '(?<="name":")[^"]*' | head -n 1)

if [ -z "$BEST_SERVER" ]; then
    echo "Failed to get active server. Falling back to store3..." >&2
    BEST_SERVER="store3"
fi

for FILE in "$@"; do
  if [ ! -f "$FILE" ]; then
    echo "\"$FILE\" not found! Skipping." >&2
    continue
  fi

  FILENAME="${FILE##*/}"
  FILESIZE=$(du -h "$FILE" | cut -f1)
  
  echo "Uploading $FILENAME ($FILESIZE) via $BEST_SERVER..." >&2

  RESPONSE=$(curl -# -F "file=@$FILE" "https://${BEST_SERVER}.gofile.io/contents/uploadfile")
  
  UPLOAD_STATUS=$(echo "$RESPONSE" | grep -o '"status":"ok"')

  if [[ -n "$UPLOAD_STATUS" ]]; then
      GOLINK=$(echo "$RESPONSE" | grep -oP '"downloadPage":"\K[^"]+')

      echo "Success!" >&2
      echo "Link: ${GOLINK}" >&2

      echo "${FILENAME}|${FILESIZE}|${GOLINK}"
      return 0
  else
      echo "Upload failed! Response: $RESPONSE" >&2
      echo "UPLOAD_FAILED"
      return 1
  fi
done
}

# =========================================================
# BUILD FUNCTION
# =========================================================

start_build_process() {
    START_TIME=$(date +%s)

    echo "Sending build start message..."
    initial_msg=$'⚙️ <b>ROM Build Started!</b>\n\n• <b>ROM:</b> '"$BUILD_TARGET"$'\n• <b>Android:</b> '"$ANDROID_VERSION"$'\n• <b>Device:</b> '"$DEVICE_CODE"$'\n• <b>Server:</b> foss.crave.io\n• <b>Start Time:</b> '"$(date '+%Y-%m-%d %H:%M:%S %Z')"
    send_telegram_msg "$TG_CHAT_ID" "$initial_msg"
    
    echo "Removing local changes..."
    rm -rf .repo/local_manifests
    rm -rf kernel/configs
    rm -rf hardware/interfaces
    rm -rf frameworks/native
    rm -rf kernel/sony
    rm -rf device/sony
    rm -rf hardware/sony
    rm -rf vendor/sony
    rm -rf vendor/lineage-priv

    echo "Set github account.."
    git config --global user.name "ganendra"
    git config --global user.email "ganendra2323@gmail.com"

    echo "Initializing repo..."
    repo init -u https://github.com/The-Clover-Project/manifest.git -b 16-qpr2 --git-lfs --depth=1

    echo "Syncing sources..."
    if [ -f /opt/crave/resync.sh ]; then
      /opt/crave/resync.sh
    fi
    repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune

    echo "Replacing some repository..."
    rm -rf kernel/configs
    rm -rf hardware/interfaces
    git clone https://github.com/crdroidandroid/android_kernel_configs -b 16.0 kernel/configs
    git clone https://github.com/crdroidandroid/android_hardware_interfaces -b 16.0 hardware/interfaces

    echo "Patch frameroks_native..."
    cd frameworks/native
    wget https://raw.githubusercontent.com/aoitsme/crave_script/refs/heads/main/patch/001-temp-fix-camera.patch
    wget https://raw.githubusercontent.com/aoitsme/crave_script/refs/heads/main/patch/002-temp-fix-camera.patch
    git am 001-temp-fix-camera.patch
    git am 002-temp-fix-camera.patch
    cd -
    
    echo "Cloning device trees..."
    git clone https://github.com/aoitsme/android_kernel_sony_sdm845 -b bpf kernel/sony/sdm845
    git clone https://github.com/aoitsme/android_device_sony_"$DEVICE_CODE" -b lineage-23.2 device/sony/"$DEVICE_CODE"
    git clone https://github.com/aoitsme/android_device_sony_tama-common -b clvr-16.2 device/sony/tama-common
    git clone https://github.com/aoitsme/android_hardware_sony_SonyOpenTelephony -b lineage-23.2 hardware/sony/SonyOpenTelephony
    git clone https://github.com/aoitsme/proprietary_vendor_sony_"$DEVICE_CODE" -b lineage-23.2 vendor/sony/"$DEVICE_CODE"
    git clone https://github.com/aoitsme/proprietary_vendor_sony_tama-common -b lineage-23.2 vendor/sony/tama-common
    git clone https://github.com/aoitsme/keys -b master vendor/lineage-priv

cd device/sony/apollo

# Rename AndroidProducts.mk: lineage_apollo -> clover_apollo
sed -i 's/lineage_apollo/clover_apollo/g' AndroidProducts.mk

# Rename file product mk
git mv lineage_apollo.mk clover_apollo.mk

# replace
cat > clover_apollo.mk << 'EOF'
#
# Copyright (C) 2018-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from apollo device
$(call inherit-product, device/sony/apollo/device.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/clover/config/common_full_phone.mk)

# Setup keystore
-include vendor/lineage-priv/keys/keys.mk

PRODUCT_NAME := clover_apollo
PRODUCT_DEVICE := apollo
PRODUCT_MANUFACTURER := Sony
PRODUCT_BRAND := Sony
PRODUCT_MODEL := Xperia XZ2 Compact

TARGET_BOOT_ANIMATION_RES := 1080
TARGET_ENABLE_BLUR := true
TARGET_DISABLE_EPPE := true

CLOVER_MAINTAINER := Ganendra1945
TARGET_SUPPORTS_QUICK_TAP := true
TARGET_FACE_UNLOCK_SUPPORTED := true
WITH_GMS := false

PRODUCT_GMS_CLIENTID_BASE := android-sony

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="H8324-user 10 52.1.A.3.49 052001A003004902006556692 release-keys" \
    BuildFingerprint=Sony/H8324/H8324:10/52.1.A.3.49/052001A003004902006556692:user/release-keys
cd -

cat > device/sony/apollo/AndroidProducts.mk << 'EOF'
#
# Copyright (C) 2018-2019 The LineageOS Project
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

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/clover_apollo.mk

COMMON_LUNCH_CHOICES := \
    clover_apollo-user \
    clover_apollo-userdebug \
    clover_apollo-eng
EOF
    
    echo "Starting ROM build..."
    . build/envsetup.sh
    lunch clover_"$DEVICE_CODE"-bp4a-userdebug
    mka clover

    BUILD_STATUS=${PIPESTATUS[0]}

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    DURATION_FORMATTED=$(format_duration $DURATION)

    if [[ $BUILD_STATUS -eq 0 ]]; then
        ZIP_FILE=$(ls -t out/target/product/"$DEVICE_CODE"/*"$DEVICE_CODE"*.zip 2>/dev/null | head -n 1)
        UPLOAD_RESULT=$(upload_files "$ZIP_FILE")

        if [[ "$UPLOAD_RESULT" != "UPLOAD_FAILED" ]]; then
            IFS='|' read -r FILENAME FILESIZE GOLINK <<< "$UPLOAD_RESULT"
            final_msg=$'⚙️ <b>ROM Build Finished!</b>\n\n• <b>ROM:</b> '"$BUILD_TARGET"$'\n• <b>Android:</b> '"$ANDROID_VERSION"$'\n• <b>Device:</b> '"$DEVICE_CODE"$'\n• <b>File:</b> '"$FILENAME"$'\n• <b>Size:</b> '"$FILESIZE"$'\n• <b>Link:</b> '"$GOLINK"$'\n• <b>Finish Time:</b> '"$(date '+%Y-%m-%d %H:%M:%S %Z')"$'\n• <b>Duration:</b> '"$DURATION_FORMATTED"$'\n• <b>Status:</b> Success'
        else
            final_msg=$'⚙️ <b>ROM Build Finished!</b>\n\n• <b>ROM:</b> '"$BUILD_TARGET"$'\n• <b>Android:</b> '"$ANDROID_VERSION"$'\n• <b>Device:</b> '"$DEVICE_CODE"$'\n• <b>Finish Time:</b> '"$(date '+%Y-%m-%d %H:%M:%S %Z')"$'\n• <b>Duration:</b> '"$DURATION_FORMATTED"$'\n• <b>Status:</b> Upload failed'
        fi
    else
        final_msg=$'⚙️ <b>ROM Build Finished!</b>\n\n• <b>ROM:</b> '"$BUILD_TARGET"$'\n• <b>Android:</b> '"$ANDROID_VERSION"$'\n• <b>Device:</b> '"$DEVICE_CODE"$'\n• <b>Finish Time:</b> '"$(date '+%Y-%m-%d %H:%M:%S %Z')"$'\n• <b>Duration:</b> '"$DURATION_FORMATTED"$'\n• <b>Status:</b> Failure (Exit Code: '"$BUILD_STATUS"$')'
    fi

    send_telegram_msg "$TG_CHAT_ID" "$final_msg"
    
    if [[ $BUILD_STATUS -ne 0 ]]; then
        send_telegram_file "$TG_CHAT_ID" "out/error.log"
    fi
}

# =========================================================
# MAIN EXECUTION
# =========================================================

case "$1" in
    --aurora)
        DEVICE_CODE="aurora"
        start_build_process
        ;;
        
    --akari)
        DEVICE_CODE="akari"
        start_build_process
        ;;
        
    --akatsuki)
        DEVICE_CODE="akatsuki"
        start_build_process
        ;;
        
    --apollo)
        DEVICE_CODE="apollo"
        start_build_process
        ;;
        
    *)
        echo "Usage: $0 [--aurora | --akari | --akatsuki | --apollo]"
        exit 1
        ;;
esac
