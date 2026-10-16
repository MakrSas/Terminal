TARGET := iphone:clang:latest:16.0
ARCHS = arm64
PACKAGE_ARCHS = iphoneos-arm64
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MakrTerminal
MakrTerminal_FILES = Sources/main.m Sources/AppDelegate.m Sources/TerminalViewController.m
MakrTerminal_FRAMEWORKS = UIKit WebKit
MakrTerminal_CFLAGS = -fobjc-arc -Wall -Wextra
MakrTerminal_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk
