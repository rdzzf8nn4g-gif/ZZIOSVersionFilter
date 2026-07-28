name: Build Theos Tweak

# 触发条件：推送到主分支，或者在 Actions 页面手动触发
on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch: 

jobs:
  build:
    name: Compile Tweak
    runs-on: macos-latest # 必须使用 macOS runner，内置 Xcode 和 ldid 环境

    env:
      # 指定 Theos 的环境变量路径
      THEOS: ${{ github.workspace }}/theos

    steps:
      - name: 📥 检出代码
        uses: actions/checkout@v4

      - name: 📦 缓存 Theos 环境
        id: cache-theos
        uses: actions/cache@v3
        with:
          path: ${{ github.workspace }}/theos
          key: ${{ runner.os }}-theos-master
          restore-keys: |
            ${{ runner.os }}-theos-

      - name: ⚙️ 安装 Theos 与 iOS SDKs
        if: steps.cache-theos.outputs.cache-hit != 'true'
        run: |
          echo ">>> 拉取 Theos 主分支..."
          git clone --recursive https://github.com/theos/theos.git $THEOS
          echo ">>> 拉取 iOS SDKs..."
          git clone https://github.com/theos/sdks.git $THEOS/sdks

      - name: 🔨 运行编译脚本
        run: |
          chmod +x build.sh
          ./build.sh

      - name: 📤 上传编译产物 (.deb)
        uses: actions/upload-artifact@v4
        with:
          name: ZZIOSVersionFilter-Packages
          path: packages/*.deb
          if-no-files-found: error
