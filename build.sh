#!/bin/bash
# 遇到错误立即退出
set -e

echo ">>> 正在修复维护者脚本换行符与权限 (防止静默失效)..."
# 强制将 CRLF(Windows) 转换为 LF(Unix)，macOS runner 完美兼容
perl -pi -e 's/\r$//' postinst postrm 2>/dev/null || true
# 赋予标准的 rwxr-xr-x 权限
chmod 0755 postinst postrm 2>/dev/null || true

echo ">>> 清理旧文件..."
make clean

echo ">>> 正在编译 Rootful (有根) 版本..."
make package

echo ">>> 正在编译 Rootless (无根) 版本..."
make package THEOS_PACKAGE_SCHEME=rootless

# 注意：Roothide 的编译在部分纯净官方 Theos 中可能需要依赖特定分支，
# 但最新版 Theos / Roothide 分支均支持此 SCHEME 命令。
echo ">>> 正在编译 Roothide (隐藏越狱) 版本..."
make package THEOS_PACKAGE_SCHEME=roothide

echo ">>> 编译完成！所有版本的 .deb 文件已生成在 packages/ 目录下。"
