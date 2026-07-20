#!/bin/bash
source shell/apk-custom-packages.sh
#echo "✅ 你选择了第三方软件包：$CUSTOM_PACKAGES"
if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 1. 同步悟空大佬的第三方软件仓库 =============
  echo "🔄 正在同步第三方软件仓库 Cloning apk file repo..."
  git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo

  # 📥 ============== 下载并解压 QModem 编译好的 arm64 apk 成品（终极稳妥版）==============
  echo "🔄 正在从 Release 下载已编译好的 QModem arm64 apk 包..."
  
  # 提前创建最终的合法包池目录
  mkdir -p /home/build/immortalwrt/packages/
  
  # 【核心改进】：加上 -L 跟踪重定向，--no-check-certificate 忽略证书问题
  wget -L --no-check-certificate https://github.com/sfwtw/QModem-custom/releases/download/v3.0.0/QModem-arm64_apk.tar.gz -O /tmp/QModem-arm64_apk.tar.gz
  
  # 严格验证下载回来的文件大小，如果小于 10KB 肯定不是真正的压缩包
  if [ -f "/tmp/QModem-arm64_apk.tar.gz" ] && [ $(stat -c%s "/tmp/QModem-arm64_apk.tar.gz") -gt 10240 ]; then
      echo "📦 压缩包下载成功，大小正常，正在解压..."
      mkdir -p /tmp/qmodem-unpacked
      tar -zxf /tmp/QModem-arm64_apk.tar.gz -C /tmp/qmodem-unpacked/
      
      # 全量搜刮解压出来的所有 apk 文件并强行塞入包池
      cp -r /tmp/qmodem-unpacked/*/*.apk /home/build/immortalwrt/packages/ 2>/dev/null || true
      cp -r /tmp/qmodem-unpacked/*.apk /home/build/immortalwrt/packages/ 2>/dev/null || true
      find /tmp/qmodem-unpacked/ -name "*.apk" -exec cp {} /home/build/immortalwrt/packages/ \; 2>/dev/null || true
      echo "✅ QModem-custom 所有 apk 已经全部强行注入 packages 目录！"
  else
      echo "❌ 警告：本地 wget 失败或下载到了空文件，启动 GitHub 原生克隆备用方案..."
      # 备用方案：直接从仓库主分支拉取源码的 assets（有些仓库会把最新编译包放在特定目录）
      git clone --depth=1 https://github.com/sfwtw/QModem-custom.git /tmp/QModem-git
      find /tmp/QModem-git/ -name "*.apk" -exec cp {} /home/build/immortalwrt/packages/ \; 2>/dev/null || true
  fi
  # =========================================================================================

  # 2. 拷贝 run/arm64 下所有 run 文件和apk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-apk-repo/run/arm64-a53/* /home/build/immortalwrt/extra-packages/ 2>/dev/null || true

  echo "✅ Run files copied to extra-packages:"
  # 解压并拷贝apk到packages目录
  sh shell/apk-prepare-packages.sh
  
  echo "🔍 正在列出最终合法包池内容，确认 qmodem 相关 apk 是否存在："
  ls -lah /home/build/immortalwrt/packages/ | grep -E "qmodem|sms-forwarder" || echo "⚠️ 糟糕，包池里依然没有找到 QModem 的 apk 文件！"
fi


# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"

echo "Include Docker: $INCLUDE_DOCKER"
echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入pppoe变量————>pppoe-settings文件
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting build process..."


# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
# 文件管理器
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"


# 第三方软件包 合并
# ======== shell/apk-custom-packages.sh =======
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"


# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
    # Download latest openclash Client
    URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest \
      | grep "browser_download_url.*apk" \
      | head -n1 \
      | cut -d '"' -f 4)
    echo "OpenClash latest apk: $URL"
    wget "$URL" -P /home/build/immortalwrt/packages/
else
    echo "⚪️ 未选择 luci-app-openclash"
fi


# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
