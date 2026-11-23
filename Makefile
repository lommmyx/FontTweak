export DEBUG=0
export FINALPACKAGE=1
export THEOS=/opt/theos

# Project name
TWEAK_NAME = FontTweak

# Architecture, SDK, and minimum deployment version
export ARCHS = arm64
TARGET = iphone:clang:26.5:16.0

# Source files
FontTweak_FILES = Hooks/GestureHooks.xm \
                  Hooks/CustomFontHooks.xm \
                  Controllers/CSFontSettingsViewController.m

FontTweak_LOGOS_DEFAULT_GENERATOR = internal
FontTweak_USE_MODULES = 0

# Compiler flags
FontTweak_CFLAGS = -fobjc-arc \
                   -I$(THEOS_PROJECT_DIR)/Headers \
                   -I$(THEOS_PROJECT_DIR)/Hooks \
                   -iframeworkwithsysroot /System/Library/SubFrameworks \
                   -Wno-error

# Framework dependencies
FontTweak_FRAMEWORKS = UIKit Foundation CoreGraphics CoreText UniformTypeIdentifiers

# Include the Theos build system
include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	@echo -e "\033[31m==>\033[0m Cleaning..."
	@rm -rf .theos

after-all::
	@echo -e "\033[32m==>\033[0m Build complete. Output directory: $(THEOS_OBJ_DIR)"
