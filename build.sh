#!/bin/zsh
# MacPulse 一键编译打包脚本
set -euo pipefail
cd "$(dirname "$0")"

unset ELECTRON_RUN_AS_NODE NODE_OPTIONS BASH_ENV

mkdir -p build/MacPulse.app/Contents/MacOS build/MacPulse.app/Contents/Resources/zh-Hans.lproj

# 中文本地化标记：让 AppKit 把「关于/服务/隐藏/退出」等系统菜单显示为中文。
# 空 strings 文件即可——这些菜单项文案来自系统框架，只要 app 声明支持中文就会本地化。
printf '/* MacPulse 简体中文本地化 */\n' > build/MacPulse.app/Contents/Resources/zh-Hans.lproj/Localizable.strings

# 安装应用图标（若已生成）
if [ -f icons/MacPulse.icns ]; then
    cp icons/MacPulse.icns build/MacPulse.app/Contents/Resources/MacPulse.icns
fi

cat > build/MacPulse.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MacPulse</string>
    <key>CFBundleIdentifier</key><string>com.xiongfeng.macpulse</string>
    <key>CFBundleName</key><string>MacPulse</string>
    <key>CFBundleDisplayName</key><string>MacPulse</string>
    <key>CFBundleIconFile</key><string>MacPulse.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>en</string>
    </array>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><false/>
</dict>
</plist>
PLIST

echo ">> 编译中..."
swiftc -O -parse-as-library Sources/*.swift -o build/MacPulse.app/Contents/MacOS/MacPulse

echo ">> ad-hoc 签名..."
codesign --force --deep --sign - build/MacPulse.app

echo ">> 完成: $(pwd)/build/MacPulse.app"
