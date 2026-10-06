THEOS_DEVICE_IP = localhost
THEOS_DEVICE_PORT = 2222
ARCHS ?= arm64 arm64e
TARGET ?= iphone:latest:14.0

BUNDLE_NAME = com.swiftyper.wechatredenvelop
ifneq ($(THEOS_PACKAGE_SCHEME),rootless)
com.swiftyper.wechatredenvelop_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
else
com.swiftyper.wechatredenvelop_INSTALL_PATH = /var/jb/Library/MobileSubstrate/DynamicLibraries
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/bundle.mk

SRC = $(wildcard src/*.m)

TWEAK_NAME = WeChatRedEnvelop
WeChatRedEnvelop_FILES = $(wildcard src/*.m) src/Tweak.xm
WeChatRedEnvelop_FRAMEWORKS = UIKit
ADDITIONAL_CFLAGS = -Wno-error
WeChatRedEnvelop_CFLAGS = -fobjc-arc -Wno-error -Wno-deprecated-declarations -Wno-arc-performSelector-leaks -Wno-unused-variable

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 WeChat"
