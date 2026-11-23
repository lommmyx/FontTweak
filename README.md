# FontTweak

Use custom fonts in an iOS host app. FontTweak targets iOS 16 through 26 on arm64 and uses the Objective-C runtime for its hooks.

## Use

Download `FontTweak.dylib` from the [latest release](../../releases/latest). Once the host app loads the library, tap three times with three fingers together to open **Font Settings**. Turn on **Enable Custom Fonts**, then use **Add Font File** to import a `.ttf` or `.otf` file and select it.

## Build

Install Theos and the iOS 26.5 SDK, then run `make`. On Linux, use an iOS cross-toolchain with compiler-rt builtins. The project defaults to Theos at `/opt/theos`. Set `THEOS` on the command line if your installation uses another path.
