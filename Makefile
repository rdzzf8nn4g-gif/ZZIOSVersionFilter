TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = zhuanzhuan

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZZIOSVersionFilter

ZZIOSVersionFilter_FILES = Tweak.x
ZZIOSVersionFilter_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
