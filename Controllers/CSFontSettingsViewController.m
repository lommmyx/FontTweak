#import "CSFontSettingsViewController.h"
#import <CoreText/CoreText.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// User defaults keys
static NSString * const kCustomFontEnabledKey = @"com.wechat.enhance.customFont.enabled";
static NSString * const kCustomFontPathKey = @"com.wechat.enhance.customFont.path";
static NSString * const kCustomFontNameKey = @"com.wechat.enhance.customFont.name";

// Font storage directory
static NSString * const kWechatEnhanceFolderName = @"WechatEnhance";

// Settings item types
typedef NS_ENUM(NSInteger, SettingItemType) {
    SettingItemTypeNormal,  
    SettingItemTypeSwitch,  
    SettingItemTypeAction   
};

// Settings item model
@interface FontSettingItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *iconName;
@property (nonatomic, strong, nullable) UIColor *iconColor;
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic, assign) SettingItemType itemType;
@property (nonatomic, assign) BOOL switchValue;
@property (nonatomic, copy, nullable) void (^switchValueChanged)(BOOL isOn);
@property (nonatomic, copy, nullable) void (^actionBlock)(void);

+ (instancetype)itemWithTitle:(NSString *)title
                     iconName:(nullable NSString *)iconName
                    iconColor:(nullable UIColor *)iconColor
                       detail:(nullable NSString *)detail;

+ (instancetype)switchItemWithTitle:(NSString *)title
                           iconName:(nullable NSString *)iconName
                          iconColor:(nullable UIColor *)iconColor
                        switchValue:(BOOL)switchValue
                  valueChangedBlock:(nullable void(^)(BOOL isOn))valueChanged;

+ (instancetype)actionItemWithTitle:(NSString *)title
                           iconName:(nullable NSString *)iconName
                          iconColor:(nullable UIColor *)iconColor;
@end

@implementation FontSettingItem

+ (instancetype)itemWithTitle:(NSString *)title iconName:(NSString *)iconName iconColor:(UIColor *)iconColor detail:(NSString *)detail {
    FontSettingItem *item = [[FontSettingItem alloc] init];
    item.title = title;
    item.iconName = iconName;
    item.iconColor = iconColor;
    item.detail = detail;
    item.itemType = SettingItemTypeNormal;
    return item;
}

+ (instancetype)switchItemWithTitle:(NSString *)title iconName:(NSString *)iconName iconColor:(UIColor *)iconColor switchValue:(BOOL)switchValue valueChangedBlock:(void (^)(BOOL))valueChanged {
    FontSettingItem *item = [[FontSettingItem alloc] init];
    item.title = title;
    item.iconName = iconName;
    item.iconColor = iconColor;
    item.switchValue = switchValue;
    item.switchValueChanged = valueChanged;
    item.itemType = SettingItemTypeSwitch;
    return item;
}

+ (instancetype)actionItemWithTitle:(NSString *)title iconName:(NSString *)iconName iconColor:(UIColor *)iconColor {
    FontSettingItem *item = [[FontSettingItem alloc] init];
    item.title = title;
    item.iconName = iconName;
    item.iconColor = iconColor;
    item.itemType = SettingItemTypeAction;
    return item;
}

@end

// Settings section model
@interface FontSettingSection : NSObject
@property (nonatomic, copy) NSString *header;
@property (nonatomic, copy, nullable) NSString *footer;
@property (nonatomic, copy) NSArray<FontSettingItem *> *items;

+ (instancetype)sectionWithHeader:(NSString *)header items:(NSArray<FontSettingItem *> *)items;
@end

@implementation FontSettingSection

+ (instancetype)sectionWithHeader:(NSString *)header items:(NSArray<FontSettingItem *> *)items {
    FontSettingSection *section = [[FontSettingSection alloc] init];
    section.header = header;
    section.items = items;
    return section;
}

@end

@interface CSFontSettingsViewController () <UIDocumentPickerDelegate, UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) NSArray<FontSettingSection *> *sections;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *fontsList;
@property (nonatomic, strong) NSString *selectedFontPath;
@property (nonatomic, strong) NSString *selectedFontName;
@property (nonatomic, strong) NSFileManager *fileManager;
@end

@implementation CSFontSettingsViewController

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Initialize the file manager.
    self.fileManager = [NSFileManager defaultManager];
    
    // Set the page title.
    self.title = @"Font Settings";

    if (@available(iOS 26.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration glassButtonConfiguration];
        configuration.image = [UIImage systemImageNamed:@"xmark"];
        UIButton *closeButton = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
        closeButton.accessibilityLabel = @"Close";
        [closeButton addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];

        UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithCustomView:closeButton];
        closeItem.hidesSharedBackground = YES;
        self.navigationItem.rightBarButtonItem = closeItem;
    } else {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                             target:self
                                                                                             action:@selector(closeSettings)];
    }
    
    // Configure the table view appearance.
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 54, 0, 0);
    
    // Register standard table view cells.
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"FontSettingCell"];
    // Register reuse identifiers for detail and switch cells.
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"FontSettingDetailCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"FontSettingSwitchCell"];
    
    // Initialize the font list.
    self.fontsList = [NSMutableArray array];
    
    // Load the font list.
    [self loadFontsList];
    
    // Populate the settings sections.
    [self setupData];
    
    // Ensure the directory exists.
    [self ensureDirectoryExists:[self getWechatEnhancePath]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Refresh the font list whenever the page appears.
    [self loadFontsList];
    [self setupData];
    [self.tableView reloadData];
}

#pragma mark - File and directory management

// Ensure the directory exists.
- (BOOL)ensureDirectoryExists:(NSString *)path {
    if (!path) return NO;
    
    BOOL isDirectory = NO;
    BOOL exists = [self.fileManager fileExistsAtPath:path isDirectory:&isDirectory];
    
    if (exists && isDirectory) {
        return YES; // The directory already exists.
    }
    
    if (exists && !isDirectory) {
        // Try removing the existing file at the directory path.
        NSError *removeError = nil;
        if (![self.fileManager removeItemAtPath:path error:&removeError]) {
            return NO; // The existing file could not be removed.
        }
    }
    
    // Create the directory.
    NSError *createError = nil;
    BOOL success = [self.fileManager createDirectoryAtPath:path 
                               withIntermediateDirectories:YES 
                                                attributes:nil 
                                                     error:&createError];
    return success;
}

// Get the font storage directory path.
- (NSString *)getWechatEnhancePath {
    // Use the Library/Preferences directory.
    NSString *libraryPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSString *preferencesPath = [libraryPath stringByAppendingPathComponent:@"Preferences"];
    NSString *enhancePath = [preferencesPath stringByAppendingPathComponent:kWechatEnhanceFolderName];
    
    // Ensure the directory exists.
    [self ensureDirectoryExists:enhancePath];
    
    return enhancePath;
}

#pragma mark - Data loading

// Load the font list.
- (void)loadFontsList {
    // Clear the current list.
    [self.fontsList removeAllObjects];
    
    // Find the font files in the storage directory.
    NSString *enhancePath = [self getWechatEnhancePath];
    
    // Ensure the directory exists.
    if (![self ensureDirectoryExists:enhancePath]) {
        return;
    }
    
    NSError *error = nil;
    NSArray *contents = [self.fileManager contentsOfDirectoryAtPath:enhancePath error:&error];
    
    if (error) {
        return;
    }
    
    // Keep only supported font files.
    NSArray *fontExtensions = @[@"ttf", @"otf"];
    for (NSString *filename in contents) {
        NSString *extension = [filename pathExtension].lowercaseString;
        if ([fontExtensions containsObject:extension]) {
            NSString *fontPath = [enhancePath stringByAppendingPathComponent:filename];
            
            // Get the file metadata.
            NSDictionary *attributes = [self.fileManager attributesOfItemAtPath:fontPath error:&error];
            NSDate *modificationDate = error ? [NSDate date] : [attributes fileModificationDate];
            
            // Try to read the font name.
            NSString *fontName = [self getFontNameFromPath:fontPath];
            
            // Add the font to the list.
            [self.fontsList addObject:@{
                @"filename": filename,
                @"path": fontPath,
                @"date": modificationDate,
                @"fontName": fontName ?: @"Unknown Font"
            }];
        }
    }
    
    // Sort by modification date, newest first.
    [self.fontsList sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        return [obj2[@"date"] compare:obj1[@"date"]];
    }];
    
    // Load the selected font path.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.selectedFontPath = [defaults objectForKey:kCustomFontPathKey];
    self.selectedFontName = [defaults objectForKey:kCustomFontNameKey];
}

// Try to read the font name from the file.
- (NSString *)getFontNameFromPath:(NSString *)fontPath {
    if (!fontPath) return nil;
    
    NSData *fontData = [NSData dataWithContentsOfFile:fontPath];
    if (!fontData) {
        return nil;
    }
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)fontData);
    if (!provider) {
        return nil;
    }
    
    CGFontRef font = CGFontCreateWithDataProvider(provider);
    
    if (!font) {
        CGDataProviderRelease(provider);
        return nil;
    }
    
    NSString *fontName = (__bridge_transfer NSString *)CGFontCopyPostScriptName(font);
    
    CGFontRelease(font);
    CGDataProviderRelease(provider);
    
    return fontName;
}

// Build the settings sections.
- (void)setupData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *allSections = [NSMutableArray array];
    
    // General settings section
    BOOL fontEnabled = [defaults boolForKey:kCustomFontEnabledKey];
    
    FontSettingItem *enableItem = [FontSettingItem switchItemWithTitle:@"Enable Custom Fonts" 
                                                          iconName:@"textformat" 
                                                         iconColor:[UIColor systemBlueColor] 
                                                       switchValue:fontEnabled
                                                 valueChangedBlock:^(BOOL isOn) {
        [defaults setBool:isOn forKey:kCustomFontEnabledKey];
        [defaults synchronize];
        // Rebuild the settings sections.
        [self setupData];
        [self.tableView reloadData];
        
        // Changing the switch requires a restart only when a font is selected.
        if (self.selectedFontPath != nil) {
            [self showRestartAlert];
        }
    }];
    
    FontSettingSection *basicSection = [FontSettingSection sectionWithHeader:@"General" 
                                                                  items:@[enableItem]];
    [allSections addObject:basicSection];
    
    // Show the following sections when custom fonts are enabled.
    if (fontEnabled) {
        // Font import section
        FontSettingItem *addFontItem = [FontSettingItem actionItemWithTitle:@"Add Font File" 
                                                               iconName:@"plus.circle.fill" 
                                                              iconColor:[UIColor systemGreenColor]];
        addFontItem.actionBlock = ^{
            [self showDocumentPicker];
        };
        
        FontSettingSection *addFontSection = [FontSettingSection sectionWithHeader:@"Add Fonts" 
                                                                        items:@[addFontItem]];
        [allSections addObject:addFontSection];
        
        // Imported fonts section
        if (self.fontsList.count > 0) {
            NSMutableArray *fontItems = [NSMutableArray array];
            
            for (NSDictionary *fontDict in self.fontsList) {
                NSString *fontPath = fontDict[@"path"];
                NSString *fontName = fontDict[@"fontName"];
                NSString *fileName = fontDict[@"filename"];
                
                // Check whether this font is selected.
                BOOL isSelected = [fontPath isEqualToString:self.selectedFontPath];
                
                // Create a settings item for each font.
                FontSettingItem *fontItem = [FontSettingItem itemWithTitle:fileName
                                                              iconName:@"textformat" 
                                                             iconColor:[UIColor systemIndigoColor]
                                                                detail:isSelected ? @"Selected" : nil];
                
                // Set the action for tapping the font.
                fontItem.actionBlock = ^{
                    [self selectFont:fontPath fontName:fontName];
                };
                
                [fontItems addObject:fontItem];
            }
            
            FontSettingSection *fontsSection = [FontSettingSection sectionWithHeader:@"Imported Fonts" 
                                                                         items:fontItems];
            [allSections addObject:fontsSection];
        }
    }
    
    // Help section
    FontSettingItem *helpItem = [FontSettingItem itemWithTitle:@"Instructions"
                                                  iconName:@"info.circle" 
                                                 iconColor:[UIColor systemBlueColor]
                                                    detail:nil];
    
    helpItem.actionBlock = ^{
        [self showHelpGuide];
    };
    
    FontSettingSection *helpSection = [FontSettingSection sectionWithHeader:@"Help" 
                                                                  items:@[helpItem]];
    [allSections addObject:helpSection];
    
    self.sections = [allSections copy];
}

#pragma mark - Event handling

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Show the document picker.
- (void)showDocumentPicker {
    // List the supported font types.
    NSArray *documentTypes = @[
        @"public.truetype-font",    // TTF
        @"public.opentype-font",    // OTF
        @"com.adobe.postscript-font"  // PostScript font
    ];
    
    // Suppress the deprecation warning.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // Create the document picker using the pre-iOS 14 API.
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] 
                                                     initWithDocumentTypes:documentTypes 
                                                     inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
    
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;
    
    [self presentViewController:documentPicker animated:YES completion:nil];
}

// Select a font.
- (void)selectFont:(NSString *)fontPath fontName:(NSString *)fontName {
    // Save the selected font.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:fontPath forKey:kCustomFontPathKey];
    [defaults setObject:fontName forKey:kCustomFontNameKey];
    [defaults synchronize];
    
    // Update the interface.
    self.selectedFontPath = fontPath;
    self.selectedFontName = fontName;
    
    // Refresh the settings.
    [self setupData];
    [self.tableView reloadData];
    
    // Show the restart prompt.
    [self showRestartAlert];
}

// Delete a font.
- (void)deleteFont:(NSString *)fontPath {
    BOOL needsRestart = NO;
    
    // Clear the selection and require a restart if this is the selected font.
    if ([fontPath isEqualToString:self.selectedFontPath]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults removeObjectForKey:kCustomFontPathKey];
        [defaults removeObjectForKey:kCustomFontNameKey];
        [defaults synchronize];
        
        self.selectedFontPath = nil;
        self.selectedFontName = nil;
        needsRestart = YES;
    }
    
    // Delete the file.
    NSError *error = nil;
    if (![self.fileManager removeItemAtPath:fontPath error:&error]) {
        // Handle a failed file deletion.
        [self showErrorAlertWithTitle:@"Deletion Failed" message:[NSString stringWithFormat:@"Could not delete the font file: %@", error.localizedDescription]];
        return;
    }
    
    // Refresh the font list.
    [self loadFontsList];
    [self setupData];
    [self.tableView reloadData];
    
    // Prompt for a restart if the selected font was deleted.
    if (needsRestart) {
        [self showAlertWithTitle:@"Selected Font Deleted" 
                        message:@"Restart the app to restore the default system font."
                destructiveTitle:@"Restart Now"
                    cancelTitle:@"Restart Later"
              destructiveAction:^{
                  exit(0); // Exit the app immediately.
              }];
    }
}

#pragma mark - Alert helpers

// Show a confirmation alert.
- (void)showAlertWithTitle:(NSString *)title 
                   message:(NSString *)message 
           destructiveTitle:(NSString *)destructiveTitle
               cancelTitle:(NSString *)cancelTitle
         destructiveAction:(void(^)(void))destructiveAction {
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    if (destructiveTitle && destructiveAction) {
        [alert addAction:[UIAlertAction actionWithTitle:destructiveTitle 
                                               style:UIAlertActionStyleDestructive 
                                             handler:^(UIAlertAction * _Nonnull action) {
            if (destructiveAction) destructiveAction();
        }]];
    }
    
    if (cancelTitle) {
        [alert addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:nil]];
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Show an error alert.
- (void)showErrorAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Show the restart prompt.
- (void)showRestartAlert {
    [self showAlertWithTitle:@"Restart Required" 
                   message:@"Restart the app to apply your font changes."
           destructiveTitle:@"Restart Now"
               cancelTitle:@"Restart Later"
         destructiveAction:^{
             exit(0); // Exit the app immediately.
         }];
}

// Show the instructions.
- (void)showHelpGuide {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Instructions"
                                                                             message:@"- Tap a font to select it.\n- Swipe left on a font to delete it.\n- Select an imported font to use it.\n- Restart the app to apply font changes."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" 
                                                        style:UIAlertActionStyleDefault 
                                                      handler:nil]];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

// Document picker delegate method for iOS 13 and later.
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self processSelectedFontFiles:urls];
}

// Handle cancellation of the document picker.
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // Optional feedback could include a sound or a light vibration.
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator prepare];
    [generator impactOccurred];
}

// Process the selected font files.
- (void)processSelectedFontFiles:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) {
        return;
    }
    
    // Show an alert with import progress.
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"Importing Fonts" 
                                                                      message:[NSString stringWithFormat:@"Processing font files... (0/%ld)", (long)urls.count]
                                                               preferredStyle:UIAlertControllerStyleAlert];
    
    [self presentViewController:loadingAlert animated:YES completion:^{
        // Copy files on a background thread.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *enhancePath = [self getWechatEnhancePath];
            
            // Ensure the directory exists.
            if (![self ensureDirectoryExists:enhancePath]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [loadingAlert dismissViewControllerAnimated:YES completion:^{
                        [self showErrorAlertWithTitle:@"Import Failed" message:@"Could not create the font storage folder."];
                    }];
                });
                return;
            }
            
            // Track import results.
            __block NSInteger successCount = 0;
            __block NSInteger failCount = 0;
            __block NSMutableArray *successFonts = [NSMutableArray array];
            
            // Use a dispatch group to wait for all imports.
            dispatch_group_t group = dispatch_group_create();
            
            // Import fonts on a serial queue to avoid concurrent writes.
            dispatch_queue_t fontQueue = dispatch_queue_create("com.wechat.enhance.fontImport", DISPATCH_QUEUE_SERIAL);
            
            // Process each selected font file.
            for (NSInteger index = 0; index < urls.count; index++) {
                NSURL *fontURL = urls[index];
                NSString *fileName = fontURL.lastPathComponent;
                NSString *destinationPath = [enhancePath stringByAppendingPathComponent:fileName];
                
                dispatch_group_enter(group);
                dispatch_async(fontQueue, ^{
                    BOOL hasAccess = [fontURL startAccessingSecurityScopedResource];
                    
                    BOOL success = NO;
                    NSString *fontName = nil;
                    
                    @try {
                        // Remove any existing file with the same name.
                        if ([self.fileManager fileExistsAtPath:destinationPath]) {
                            NSError *removeError = nil;
                            [self.fileManager removeItemAtPath:destinationPath error:&removeError];
                        }
                        
                        // Try copying the file directly.
                        NSError *copyError = nil;
                        if ([self.fileManager copyItemAtURL:fontURL toURL:[NSURL fileURLWithPath:destinationPath] error:&copyError]) {
                            // Validate the copied font file.
                            fontName = [self getFontNameFromPath:destinationPath];
                            if (fontName) {
                                success = YES;
                                
                                // Record the imported font.
                                dispatch_sync(dispatch_get_main_queue(), ^{
                                    [successFonts addObject:@{
                                        @"fileName": fileName,
                                        @"fontName": fontName
                                    }];
                                });
                            } else {
                                // Delete the file if its font name is invalid.
                                [self.fileManager removeItemAtPath:destinationPath error:nil];
                            }
                        } 
                        // Fall back to reading and writing the file data.
                        else {
                            NSData *fontData = [NSData dataWithContentsOfURL:fontURL options:NSDataReadingMappedIfSafe error:nil];
                            
                            if (fontData && [fontData writeToFile:destinationPath options:NSDataWritingAtomic error:nil]) {
                                // Validate the copied font file.
                                fontName = [self getFontNameFromPath:destinationPath];
                                if (fontName) {
                                    success = YES;
                                    
                                    dispatch_sync(dispatch_get_main_queue(), ^{
                                        [successFonts addObject:@{
                                            @"fileName": fileName,
                                            @"fontName": fontName
                                        }];
                                    });
                                } else {
                                    // Delete the file if its font name is invalid.
                                    [self.fileManager removeItemAtPath:destinationPath error:nil];
                                }
                            }
                        }
                    } @catch (NSException *exception) {
                        // Handle import exceptions.
                    } @finally {
                        // Stop accessing the security-scoped resource.
                        if (hasAccess) {
                            [fontURL stopAccessingSecurityScopedResource];
                        }
                        
                        // Update the import counters.
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            if (success) {
                                successCount++;
                            } else {
                                failCount++;
                            }
                            
                            // Update the progress alert.
                            NSInteger processed = successCount + failCount;
                            loadingAlert.message = [NSString stringWithFormat:@"Processing font files... (%ld/%ld)", (long)processed, (long)urls.count];
                        });
                        
                        dispatch_group_leave(group);
                    }
                });
            }
            
            // Wait for all font imports to finish.
            dispatch_group_notify(group, dispatch_get_main_queue(), ^{
                // Dismiss the progress alert.
                [loadingAlert dismissViewControllerAnimated:YES completion:^{
                    // Show the import results.
                    if (successCount > 0) {
                        NSString *resultMessage;
                        if (failCount > 0) {
                            resultMessage = [NSString stringWithFormat:@"Font files imported: %ld. Files that failed to import: %ld.", (long)successCount, (long)failCount];
                        } else {
                            resultMessage = [NSString stringWithFormat:@"Font files imported: %ld.", (long)successCount];
                        }
                        
                        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Import Complete" 
                                                                                       message:resultMessage
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                        [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            // Refresh the font list.
                            [self loadFontsList];
                            [self setupData];
                            [self.tableView reloadData];
                        }]];
                        [self presentViewController:successAlert animated:YES completion:nil];
                    } else if (failCount > 0) {
                        [self showErrorAlertWithTitle:@"Import Failed" message:@"Could not import any files. Make sure you selected valid font files."];
                    }
                }];
            });
        });
    }];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    FontSettingItem *item = self.sections[indexPath.section].items[indexPath.row];
    UITableViewCell *cell;
    
    if (item.itemType == SettingItemTypeSwitch) {
        // Use the standard cell style.
        cell = [tableView dequeueReusableCellWithIdentifier:@"FontSettingSwitchCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"FontSettingSwitchCell"];
        }
        
        // Configure the cell.
        cell.textLabel.text = item.title;
        
        if (item.iconName) {
            UIImage *icon = [UIImage systemImageNamed:item.iconName];
            cell.imageView.image = icon;
            cell.imageView.tintColor = item.iconColor;
        } else {
            cell.imageView.image = nil;
        }
        
        // Create the switch.
        UISwitch *switchControl = [[UISwitch alloc] initWithFrame:CGRectZero];
        switchControl.on = item.switchValue;
        switchControl.tag = indexPath.section * 1000 + indexPath.row; // Use the tag to identify the settings item when the switch changes.
        [switchControl addTarget:self action:@selector(switchValueChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchControl;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (item.detail) {
        // Use the cell style with detail text.
        cell = [tableView dequeueReusableCellWithIdentifier:@"FontSettingDetailCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"FontSettingDetailCell"];
        }
        
        // Configure the cell.
        cell.textLabel.text = item.title;
        cell.detailTextLabel.text = item.detail;
        
        if (item.iconName) {
            UIImage *icon = [UIImage systemImageNamed:item.iconName];
            cell.imageView.image = icon;
            cell.imageView.tintColor = item.iconColor;
        } else {
            cell.imageView.image = nil;
        }
        
        // Configure the accessory for this item type.
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        // Use the standard cell style.
        cell = [tableView dequeueReusableCellWithIdentifier:@"FontSettingCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"FontSettingCell"];
        }
        
        // Configure the cell.
        cell.textLabel.text = item.title;
        
        if (item.iconName) {
            UIImage *icon = [UIImage systemImageNamed:item.iconName];
            cell.imageView.image = icon;
            cell.imageView.tintColor = item.iconColor;
        } else {
            cell.imageView.image = nil;
        }
        
        // Configure the accessory for this item type.
        if (item.itemType == SettingItemTypeAction) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section].header;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    FontSettingItem *item = self.sections[indexPath.section].items[indexPath.row];
    
    // Run the action block if one is set.
    if (item.actionBlock) {
        item.actionBlock();
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

// Support swipe-to-delete for fonts.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only font list rows can be edited.
    return [self.sections[indexPath.section].header isEqualToString:@"Imported Fonts"];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.sections[indexPath.section].header isEqualToString:@"Imported Fonts"]) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && 
        [self.sections[indexPath.section].header isEqualToString:@"Imported Fonts"]) {
        
        // Get the font to delete.
        NSDictionary *fontDict = self.fontsList[indexPath.row];
        NSString *fontPath = fontDict[@"path"];
        
        // Show the deletion confirmation.
        [self showAlertWithTitle:@"Delete Font?" 
                        message:@"Are you sure you want to delete this font file?"
                destructiveTitle:@"Delete"
                    cancelTitle:@"Cancel"
              destructiveAction:^{
                  [self deleteFont:fontPath];
              }];
    }
}

// Use the switch tag to find the settings item.
- (void)switchValueChanged:(UISwitch *)sender {
    NSInteger section = sender.tag / 1000;
    NSInteger row = sender.tag % 1000;
    
    // Validate the section and row indexes.
    if (section < self.sections.count) {
        FontSettingSection *settingSection = self.sections[section];
        if (row < settingSection.items.count) {
            FontSettingItem *item = settingSection.items[row];
            
            // Update the settings item's state.
            item.switchValue = sender.isOn;
            
            // Run the callback.
            if (item.switchValueChanged) {
                item.switchValueChanged(sender.isOn);
            }
        }
    }
}

@end 
