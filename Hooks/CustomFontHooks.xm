// CustomFontHooks.xm

#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>

// Preference keys
static NSString *const kCustomFontEnabledKey = @"com.wechat.enhance.customFont.enabled";
static NSString *const kCustomFontPathKey = @"com.wechat.enhance.customFont.path";
static NSString *const kCustomFontNameKey = @"com.wechat.enhance.customFont.name";

// Global variables
static BOOL g_customFontEnabled = NO;
static BOOL g_fontLoaded = NO;
static NSString *g_customFontName = nil;
static NSString *g_customFontFamilyName = nil;
static CGFloat g_fontSizeOffset = 0.0;
static NSString *g_selectedFontPath = nil;
static BOOL g_isCreatingCustomFont = NO; // Guard against recursive font creation.

// Load the custom font.
static BOOL loadCustomFont() {
    if (g_fontLoaded) {
        return YES;
    }
    
    // Read the selected font path from user defaults.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *selectedFontPath = [defaults objectForKey:kCustomFontPathKey];
    NSString *selectedFontName = [defaults objectForKey:kCustomFontNameKey];
    
    // Use the font path saved by the settings controller.
    NSString *fontPath = selectedFontPath;
    if (!fontPath) {
        // Return when no font path has been selected.
        return NO;
    }
    
    g_selectedFontPath = fontPath;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:fontPath]) {
        // Return if the font file is missing.
        return NO;
    }
    
    NSData *fontData = [NSData dataWithContentsOfFile:fontPath];
    if (!fontData) {
        return NO;
    }
    
    // Register the font.
    CFErrorRef error = NULL;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)fontData);
    CGFontRef font = CGFontCreateWithDataProvider(provider);
    BOOL success = CTFontManagerRegisterGraphicsFont(font, &error);
    
    if (!success) {
        if (error) CFRelease(error);
    } else {
        // Use the selected font name when available.
        if (selectedFontName) {
            g_customFontName = [selectedFontName copy];
        } else {
            // Get the registered font name and family name.
            NSString *fontName = (__bridge_transfer NSString *)CGFontCopyPostScriptName(font);
            g_customFontName = [fontName copy];
        }
        
        // Create a temporary font to get more information.
        CTFontRef tempFont = CTFontCreateWithGraphicsFont(font, 12.0, NULL, NULL);
        if (tempFont) {
            // Get the font family name.
            g_customFontFamilyName = (__bridge_transfer NSString *)CTFontCopyFamilyName(tempFont);
            
            CFRelease(tempFont);
        }
        
        g_fontLoaded = YES;
    }
    
    // Release resources.
    if (font) CGFontRelease(font);
    if (provider) CGDataProviderRelease(provider);
    
    return success;
}

// Load the saved settings.
static void loadSettings() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    g_customFontEnabled = [defaults boolForKey:kCustomFontEnabledKey];
    g_selectedFontPath = [defaults objectForKey:kCustomFontPathKey];
}

// Create custom fonts in one place.
static UIFont *createCustomFont(CGFloat size) {
    if (!g_customFontEnabled || !g_fontLoaded || !g_customFontName) {
        return nil;
    }
    
    // Try several ways to create the font.
    UIFont *customFont = nil;
    
    // Try the saved PostScript name.
    g_isCreatingCustomFont = YES; // Set the recursion guard before creating the font.
    customFont = [UIFont fontWithName:g_customFontName size:size + g_fontSizeOffset];
    g_isCreatingCustomFont = NO; // Clear the recursion guard after creating the font.
    if (customFont) {
        return customFont;
    }
    
    // Try the first font in the family.
    if (g_customFontFamilyName) {
        g_isCreatingCustomFont = YES; // Set the recursion guard before creating the font.
        NSArray *fontsInFamily = [UIFont fontNamesForFamilyName:g_customFontFamilyName];
        g_isCreatingCustomFont = NO; // Clear the recursion guard after creating the font.
        if (fontsInFamily.count > 0) {
            g_isCreatingCustomFont = YES; // Set the recursion guard before creating the font.
            customFont = [UIFont fontWithName:fontsInFamily[0] size:size + g_fontSizeOffset];
            g_isCreatingCustomFont = NO; // Clear the recursion guard after creating the font.
            if (customFont) {
                return customFont;
            }
        }
    }
    
    // Try using the file name as the font name.
    if (g_selectedFontPath) {
        NSString *fontFileName = [[g_selectedFontPath lastPathComponent] stringByDeletingPathExtension];
        g_isCreatingCustomFont = YES; // Set the recursion guard before creating the font.
        customFont = [UIFont fontWithName:fontFileName size:size + g_fontSizeOffset];
        g_isCreatingCustomFont = NO; // Clear the recursion guard after creating the font.
        if (customFont) {
            return customFont;
        }
    }
    
    return nil;
}

%hook UIFont

+ (UIFont *)systemFontOfSize:(CGFloat)fontSize {
    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    UIFont *customFont = createCustomFont(fontSize);
    if (customFont) {
        return customFont;
    }
    
    id origFont = %orig;
    return origFont;
}

+ (UIFont *)systemFontOfSize:(CGFloat)fontSize weight:(CGFloat)weight {
    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    UIFont *customFont = createCustomFont(fontSize);
    if (customFont) {
        // Try to apply the requested font weight.
        if (weight != UIFontWeightRegular) {
            UIFontDescriptor *descriptor = [customFont.fontDescriptor fontDescriptorWithSymbolicTraits:
                (weight > UIFontWeightRegular) ? UIFontDescriptorTraitBold : 0];
            UIFont *weightedFont = [UIFont fontWithDescriptor:descriptor size:fontSize + g_fontSizeOffset];
            if (weightedFont) {
                return weightedFont;
            }
        }
        return customFont;
    }
    
    id origFont = %orig;
    return origFont;
}

// Hook additional font creation methods.
+ (UIFont *)fontWithName:(NSString *)fontName size:(CGFloat)fontSize {
    // Check whether custom font creation is already in progress.
    if (g_isCreatingCustomFont) {
        return %orig;
    }
    
    if (g_customFontEnabled) { // Check whether custom fonts are enabled.
        if (!g_fontLoaded) {
            loadCustomFont();
        }
        
        UIFont *customFont = createCustomFont(fontSize);
        if (customFont) {
            return customFont;
        }
    }
    
    id origFont = %orig;
    return origFont;
}

%end

// Hook table view header fonts.
%hook UITableViewHeaderFooterView

- (void)setTextLabel:(UILabel *)textLabel {
    %orig;
    
    // Apply the custom font after setTextLabel.
    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    if (g_customFontEnabled && g_fontLoaded && textLabel) {
        UIFont *originalFont = textLabel.font;
        if (originalFont) {
            UIFont *customFont = createCustomFont(originalFont.pointSize);
            if (customFont) {
                textLabel.font = customFont;
            }
        }
    }
}

- (void)layoutSubviews {
    %orig;
    
    // Reapply the font after layout in case UIKit reset it.
    if (g_customFontEnabled && g_fontLoaded && self.textLabel) {
        UIFont *originalFont = self.textLabel.font;
        if (originalFont) {
            UIFont *customFont = createCustomFont(originalFont.pointSize);
            if (customFont) {
                self.textLabel.font = customFont;
            }
        }
    }
}

%end

// Hook additional table view font methods.
%hook UITableView

// Hook the header font getter.
- (UIFont *)_sectionHeaderTitleFont {
    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    UIFont *origFont = %orig;
    if (g_customFontEnabled && g_fontLoaded && origFont) {
        UIFont *customFont = createCustomFont(origFont.pointSize);
        if (customFont) {
            return customFont;
        }
    }
    
    return origFont;
}

// Hook the footer font getter.
- (UIFont *)_sectionFooterTitleFont {
    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    UIFont *origFont = %orig;
    if (g_customFontEnabled && g_fontLoaded && origFont) {
        UIFont *customFont = createCustomFont(origFont.pointSize);
        if (customFont) {
            return customFont;
        }
    }
    
    return origFont;
}

%end

// Hook table view cells.
%hook UITableViewCell

- (void)setTextLabel:(UILabel *)textLabel {
    %orig;
    
    // Apply the custom font as soon as the text label is set.
    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    if (g_customFontEnabled && g_fontLoaded && textLabel) {
        UIFont *originalFont = textLabel.font;
        if (originalFont) {
            UIFont *customFont = createCustomFont(originalFont.pointSize);
            if (customFont) {
                textLabel.font = customFont;
            }
        }
    }
}

- (void)setDetailTextLabel:(UILabel *)detailTextLabel {
    %orig;

    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    if (g_customFontEnabled && g_fontLoaded && detailTextLabel) {
        UIFont *originalFont = detailTextLabel.font;
        if (originalFont) {
            UIFont *customFont = createCustomFont(originalFont.pointSize);
            if (customFont) {
                detailTextLabel.font = customFont;
            }
        }
    }
}

- (void)layoutSubviews {
    %orig;
    
    // Reapply the font after layout in case UIKit reset it.
    if (g_customFontEnabled && g_fontLoaded) {
        // Update the main label.
        if (self.textLabel) {
            UIFont *originalFont = self.textLabel.font;
            if (originalFont) {
                UIFont *customFont = createCustomFont(originalFont.pointSize);
                if (customFont) {
                    self.textLabel.font = customFont;
                }
            }
        }
        
        // Update the detail label.
        if (self.detailTextLabel) {
            UIFont *originalFont = self.detailTextLabel.font;
            if (originalFont) {
                UIFont *customFont = createCustomFont(originalFont.pointSize);
                if (customFont) {
                    self.detailTextLabel.font = customFont;
                }
            }
        }
    }
}

%end

// Hook UILabel to catch font changes made outside the other hooks.
%hook UILabel

- (void)setFont:(UIFont *)font {
    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    // Replace the font.
    if (g_customFontEnabled && g_fontLoaded && font) {
            UIFont *customFont = createCustomFont(font.pointSize);
            if (customFont) {
                %orig(customFont);
                return;
        }
    }
    
    %orig;
}

// Hook the initializer.
- (id)initWithFrame:(CGRect)frame {
    id orig = %orig;
    
    if (g_customFontEnabled && g_fontLoaded && orig) {
        UILabel *label = (UILabel *)orig;
        if (label.font) {
            UIFont *customFont = createCustomFont(label.font.pointSize);
            if (customFont) {
                label.font = customFont;
            }
        }
    }
    
    return orig;
}

// Handle direct access to the font property.
- (UIFont *)font {
    UIFont *originalFont = %orig;
    
    // Replace the font whenever a custom font is available.
    if (g_customFontEnabled && g_fontLoaded && originalFont) {
            UIFont *customFont = createCustomFont(originalFont.pointSize);
            if (customFont) {
                return customFont;
        }
    }
    
    return originalFont;
}

// Handle setAttributedText.
- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (g_customFontEnabled && !g_fontLoaded) {
        loadCustomFont();
    }
    
    if (g_customFontEnabled && g_fontLoaded && attributedText) {
        NSMutableAttributedString *mutableAttributedText = [attributedText mutableCopy];
        __block BOOL fontChanged = NO; 
        
        // Find and replace fonts in the attributed string.
        [mutableAttributedText enumerateAttribute:NSFontAttributeName 
                                          inRange:NSMakeRange(0, mutableAttributedText.length) 
                                          options:0 
                                       usingBlock:^(id value, NSRange range, BOOL *stop) {
            if (value && [value isKindOfClass:[UIFont class]]) {
                UIFont *originalFont = (UIFont *)value;
                UIFont *customFont = createCustomFont(originalFont.pointSize);
                if (customFont) {
                    [mutableAttributedText removeAttribute:NSFontAttributeName range:range];
                    [mutableAttributedText addAttribute:NSFontAttributeName value:customFont range:range];
                    fontChanged = YES;
                }
            }
        }];
        
        // Pass the updated string to the original method if any fonts changed.
        if (fontChanged) {
            %orig(mutableAttributedText);
            return;
        }
    }
    
    // Use the original method when custom fonts are disabled or unavailable.
    %orig;
}

%end

// Tweak entry point
%ctor {
    // Load the saved settings.
    loadSettings();
    
    // Preload the custom font.
    if (g_customFontEnabled) {
        loadCustomFont();
    }
} 