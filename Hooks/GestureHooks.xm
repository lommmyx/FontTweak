#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../Controllers/CSFontSettingsViewController.h"

static char kFontSettingsGestureKey;

@interface CSFontSettingsGestureHandler : NSObject <UIGestureRecognizerDelegate>
- (void)attachToKeyWindow:(UIWindow *)window;
@end

@implementation CSFontSettingsGestureHandler

- (void)attachToKeyWindow:(UIWindow *)window {
    if (!window.isKeyWindow) {
        return;
    }

    UITapGestureRecognizer *existing = objc_getAssociatedObject(window, &kFontSettingsGestureKey);
    if (existing.view == window) {
        return;
    }

    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openSettings:)];
    gesture.numberOfTapsRequired = 3;
    gesture.numberOfTouchesRequired = 3;
    gesture.cancelsTouchesInView = NO;
    gesture.delegate = self;
    [window addGestureRecognizer:gesture];
    objc_setAssociatedObject(window, &kFontSettingsGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[FontTweak] Registered the three-finger triple-tap gesture on a key window.");
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)openSettings:(UITapGestureRecognizer *)gesture {
    UIWindow *window = (UIWindow *)gesture.view;
    if (!window.isKeyWindow) {
        return;
    }

    UIViewController *presenter = window.rootViewController;
    while (presenter) {
        if ([presenter isKindOfClass:[CSFontSettingsViewController class]]) {
            return;
        }

        UIViewController *child = presenter.presentedViewController;
        if (!child && [presenter isKindOfClass:[UINavigationController class]]) {
            child = ((UINavigationController *)presenter).visibleViewController;
        } else if (!child && [presenter isKindOfClass:[UITabBarController class]]) {
            child = ((UITabBarController *)presenter).selectedViewController;
        }

        if (!child) {
            break;
        }
        presenter = child;
    }

    if (presenter.viewIfLoaded.window != window || presenter.isBeingDismissed) {
        return;
    }

    CSFontSettingsViewController *settings = [[CSFontSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:settings];
    navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    NSLog(@"[FontTweak] Three-finger triple tap detected. Opening Font Settings.");
    [presenter presentViewController:navigationController animated:YES completion:nil];

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
}

@end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        CSFontSettingsGestureHandler *handler = [[CSFontSettingsGestureHandler alloc] init];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeKeyNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *notification) {
            [handler attachToKeyWindow:notification.object];
        }];

        UIApplication *application = [UIApplication sharedApplication];
        NSSet<UIScene *> *scenes = application.connectedScenes;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                [handler attachToKeyWindow:((UIWindowScene *)scene).keyWindow];
            }
        }

        if (scenes.count == 0) {
            // Apps without scenes can already have a key window when the library loads.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [handler attachToKeyWindow:application.keyWindow];
#pragma clang diagnostic pop
        }
    });
}
