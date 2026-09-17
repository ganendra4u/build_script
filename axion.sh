#!/bin/bash

# =========================================================
# CONFIGURATION
# =========================================================
# This token was retrieved from your previous log for continuous functionality.
TG_BOT_TOKEN=$(echo "8653985889:AAEKKInaZBsLpWIJKuRvhhMoz2tHXePD598")
TG_CHAT_ID=$(echo "-1004210759398")
DEVICE_CODE="unknown"
BUILD_TARGET="AxionOS"
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
    rm -rf kernel/sony
    rm -rf device/sony
    rm -rf hardware/sony
    rm -rf vendor/sony
    rm -rf vendor/lineage-priv

    echo "Set github account.."
    git config --global user.name "ganendra"
    git config --global user.email "ganendra2323@gmail.com"

    echo "Initializing repo..."
    repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.2 --git-lfs --depth=1

    echo "Syncing sources..."
    if [ -f /opt/crave/resync.sh ]; then
      /opt/crave/resync.sh
    fi
    repo sync
    
    echo "Patch frameroks_native..."
    cd frameworks/native
    wget https://raw.githubusercontent.com/aoitsme/crave_script/refs/heads/main/patch/001-temp-fix-camera.patch
    wget https://raw.githubusercontent.com/aoitsme/crave_script/refs/heads/main/patch/002-temp-fix-camera.patch
    git am 001-temp-fix-camera.patch
    git am 002-temp-fix-camera.patch
    cd -
    
    echo "Cloning device trees..."
    git clone https://github.com/aoitsme/android_kernel_sony_sdm845 -b bpf --depth=1 kernel/sony/sdm845
    git clone https://github.com/ganendra4u/android_device_sony_"$DEVICE_CODE" -b lineage-23.2 --depth=1 device/sony/"$DEVICE_CODE"
    git clone https://github.com/aoitsme/android_device_sony_tama-common -b lineage-23.2 --depth=1 device/sony/tama-common
    git clone https://github.com/aoitsme/android_hardware_sony_SonyOpenTelephony -b lineage-23.2 --depth=1 hardware/sony/SonyOpenTelephony
    git clone https://github.com/aoitsme/proprietary_vendor_sony_"$DEVICE_CODE" -b lineage-23.2 --depth=1 vendor/sony/"$DEVICE_CODE"
    git clone https://github.com/aoitsme/proprietary_vendor_sony_tama-common -b lineage-23.2 --depth=1 vendor/sony/tama-common
    git clone https://github.com/aoi-itsme/keys -b new --depth=1 vendor/lineage-priv
    git clone https://github.com/swiitch-OFF-Lab/hardware_dolby hardware/dolby --depth=1

sed -i \
  -e 's/^\(\s*DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE\) :=/\1 +=/' \
  -e 's/^\(\s*DEVICE_MANIFEST_FILE\) :=/\1 +=/' \
  device/sony/tama-common/BoardConfigCommon.mk

grep -q "hardware/dolby/dolby.mk" device/sony/tama-common/common.mk || \
sed -i '1i # Dolby\n$(call inherit-product-if-exists, hardware/dolby/dolby.mk)' device/sony/tama-common/common.mk

sed -i '/vendor.audio.dolby.ds2.enabled/d;/vendor.audio.dolby.ds2.hardbypass/d' device/sony/tama-common/vendor.prop

python3 - <<'EOF'
path = "device/sony/tama-common/audio/audio_effects.xml"
with open(path) as f:
    content = f.read()

libs = '''        <!--DOLBY DAP-->
        <library name="dap" path="libswdap.so"/>
        <library name="dvl" path="libdlbvol.so"/>
        <!--DOLBY END-->
        <!--DOLBY GAME-->
        <library name="gamedap" path="libswgamedap.so"/>
        <!--DOLBY END-->
        <!--DOLBY VQE-->
        <library name="vqe" path="libswvqe.so"/>
        <!--DOLBY END-->
'''
effects = '''        <!--DOLBY DAP-->
        <effect name="dap" library="dap" uuid="9d4921da-8225-4f29-aefa-39537a04bcaa"/>
        <effect name="dlb_music_listener" library="dvl" uuid="40f66c8b-5aa5-4345-8919-53ec431aaa98"/>
        <effect name="dlb_ring_listener" library="dvl" uuid="21d14087-558a-4f21-94a9-5002dce64bce"/>
        <effect name="dlb_alarm_listener" library="dvl" uuid="6aff229c-30c6-4cc8-9957-dbfe5c1bd7f6"/>
        <effect name="dlb_system_listener" library="dvl" uuid="874db4d8-051d-4b7b-bd95-a3bebc837e9e"/>
        <effect name="dlb_notification_listener" library="dvl" uuid="1f0091e3-6ad8-40fe-9b09-5948f9a26e7e"/>
        <effect name="dlb_voice_call_listener" library="dvl" uuid="58d13383-b41d-05df-d94e-bb23db293260"/>
        <!--DOLBY END-->
        <!--DOLBY GAME-->
        <effect name="gamedap" library="gamedap" uuid="3783c334-d3a0-4d13-874f-0032e5fb80e2"/>
        <!--DOLBY END-->
        <!--DOLBY VQE-->
        <effect name="vqe" library="vqe" uuid="64a0f614-7fa4-48b8-b081-d59dc954616f"/>
        <!--DOLBY END-->
'''
if "DOLBY DAP" not in content:
    content = content.replace("</libraries>", libs + "    </libraries>", 1)
    content = content.replace("</effects>", effects + "    </effects>", 1)
    with open(path, "w") as f:
        f.write(content)
    print("audio_effects.xml updated")
else:
    print("skip!")
EOF
    
echo 'PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false' >> device/*/"$DEVICE_CODE"/device.mk

echo "Injecting AxionOS sepolicy fixes..."
    mkdir -p device/sony/"$DEVICE_CODE"/sepolicy/vendor
    cat > device/sony/"$DEVICE_CODE"/sepolicy/vendor/battery.te << 'EOF'
typealias sysfs_battery_supply alias vendor_sysfs_battery_supply;
typealias sysfs_devfreq alias vendor_sysfs_devfreq;
typealias sysfs_kgsl alias vendor_sysfs_kgsl;
EOF

    if ! grep -q "VENDOR_SEPOLICY_DIRS" device/sony/"$DEVICE_CODE"/BoardConfig.mk; then
        echo 'BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor' >> device/sony/"$DEVICE_CODE"/BoardConfig.mk
    fi

    echo "Removing duplicate sepolicy entry from tama-common..."
    sed -i '/genfscon proc \/sys\/kernel\/sched_autogroup_enabled/d' device/sony/tama-common/sepolicy/vendor/genfs_contexts

    echo "Injecting AxionOS device properties..."
    cat >> device/sony/"$DEVICE_CODE"/lineage_"$DEVICE_CODE".mk << 'EOF'
    
    # Camera information (multiple sensors supported)
AXION_CAMERA_REAR_INFO := 19
AXION_CAMERA_FRONT_INFO := 5

# Maintainer name (underscores become spaces in the UI)
AXION_MAINTAINER := Ganendra1945

# Processor name (underscores become spaces)
AXION_PROCESSOR := Snapdragon_845
EOF

    echo "Starting ROM build..."
    . build/envsetup.sh
    lunch lineage_apollo-bp4a-user
    m bacon 2>1 | tee error.log

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
