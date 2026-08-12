// =============================================================
//  DouyinDiagnostic — 纯诊断插件（不修改视图，不闪退）
//  功能：记录抖音启动时的完整 UI 结构
//  日志路径：Documents/DouyinDiagnostic.log
// =============================================================
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL DYShouldApply() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.ss.iphone.ugc.Aweme"];
}

// ---------- 日志写入 ----------
static void DYWriteLog(NSString *format, ...) {
    if (!DYShouldApply()) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *logPath = [paths.firstObject stringByAppendingPathComponent:@"DouyinDiagnostic.log"];
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fileHandle) {
        [logEntry writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
}

// ---------- 递归打印视图层级 ----------
static void DYDumpViewHierarchy(UIView *view, NSInteger depth, NSMutableString *dump) {
    if (!view) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *className = NSStringFromClass([view class]);
    NSString *frame = NSStringFromCGRect(view.frame);
    [dump appendFormat:@"%@%@ frame:%@\n", indent, className, frame];
    for (UIView *sub in view.subviews) {
        DYDumpViewHierarchy(sub, depth + 1, dump);
    }
}

// ---------- 递归打印控制器层级 ----------
static void DYDumpViewControllerHierarchy(UIViewController *vc, NSInteger depth, NSMutableString *dump) {
    if (!vc) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *className = NSStringFromClass([vc class]);
    NSString *title = vc.title ?: @"(无标题)";
    [dump appendFormat:@"%@VC: %@ 标题: %@\n", indent, className, title];
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tbc = (UITabBarController *)vc;
        [dump appendFormat:@"%@  TabBarController viewControllers (%lu):\n", indent, (unsigned long)tbc.viewControllers.count];
        for (NSInteger i = 0; i < tbc.viewControllers.count; i++) {
            UIViewController *child = tbc.viewControllers[i];
            NSString *childTitle = child.tabBarItem.title ?: @"(无标题)";
            [dump appendFormat:@"%@    [%ld] %@ (%@)\n", indent, (long)i, childTitle, NSStringFromClass([child class])];
        }
    }
    for (UIViewController *child in vc.childViewControllers) {
        DYDumpViewControllerHierarchy(child, depth + 1, dump);
    }
}

// ---------- 诊断主函数 ----------
static void DYRunDiagnostic(void) {
    NSMutableString *dump = [NSMutableString stringWithString:@"=== 抖音 UI 诊断 ===\n"];
    
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        [dump appendFormat:@"\n--- Window: %@ frame:%@ ---\n", NSStringFromClass([window class]), NSStringFromCGRect(window.frame)];
    }
    
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    if (keyWindow && keyWindow.rootViewController) {
        [dump appendString:@"\n--- 控制器层级 ---\n"];
        DYDumpViewControllerHierarchy(keyWindow.rootViewController, 0, dump);
    }
    
    UIViewController *rootVC = keyWindow.rootViewController;
    __block UITabBarController *tabBarController = nil;
    void (^findTabBarController)(UIViewController *) = ^(UIViewController *vc) {
        if ([vc isKindOfClass:[UITabBarController class]]) {
            tabBarController = (UITabBarController *)vc;
            return;
        }
        for (UIViewController *child in vc.childViewControllers) {
            findTabBarController(child);
            if (tabBarController) break;
        }
    };
    if (rootVC) {
        findTabBarController(rootVC);
    }
    
    if (tabBarController) {
        [dump appendString:@"\n--- 找到 TabBarController ---\n"];
        [dump appendFormat:@"类名: %@\n", NSStringFromClass([tabBarController class])];
        [dump appendFormat:@"viewControllers (%lu):\n", (unsigned long)tabBarController.viewControllers.count];
        for (NSInteger i = 0; i < tabBarController.viewControllers.count; i++) {
            UIViewController *vc = tabBarController.viewControllers[i];
            NSString *title = vc.tabBarItem.title ?: @"(无标题)";
            [dump appendFormat:@"  [%ld] %@ (%@)\n", (long)i, title, NSStringFromClass([vc class])];
        }
        if (tabBarController.tabBar) {
            [dump appendString:@"\n--- tabBar 子视图 ---\n"];
            for (UIView *sub in tabBarController.tabBar.subviews) {
                NSString *className = NSStringFromClass([sub class]);
                NSString *title = nil;
                if ([sub respondsToSelector:@selector(title)]) {
                    @try {
                        title = [sub valueForKey:@"title"];
                    } @catch (NSException *e) {}
                }
                if (!title) {
                    title = sub.accessibilityLabel ?: @"(无标题)";
                }
                [dump appendFormat:@"  %@ | 标题: %@ | frame:%@\n", className, title, NSStringFromCGRect(sub.frame)];
            }
        }
    } else {
        [dump appendString:@"\n未找到 TabBarController\n"];
    }
    
    if (keyWindow) {
        [dump appendString:@"\n--- 视图层级 ---\n"];
        DYDumpViewHierarchy(keyWindow, 0, dump);
    }
    
    DYWriteLog(@"%@", dump);
}

%ctor {
    if (DYShouldApply()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DYRunDiagnostic();
            DYWriteLog(@"诊断完成");
        });
    }
}
