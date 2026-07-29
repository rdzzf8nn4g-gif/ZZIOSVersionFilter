#import <UIKit/UIKit.h>

static BOOL isRadarActive = NO;
static NSMutableArray *globalURLList = nil;
static __weak UIViewController *globalVC = nil;

// ====== 1. 监听苹果最底层的网络引擎，绝不漏掉 Swift 和 Flutter ======
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)completionHandler {
    if (isRadarActive && request.URL) {
        NSString *urlStr = request.URL.absoluteString;
        if ([urlStr hasPrefix:@"http"] && ![urlStr containsString:@".jpg"] && ![urlStr containsString:@".png"] && ![urlStr containsString:@".mp4"]) {
            if (!globalURLList) globalURLList = [NSMutableArray array];
            if (![globalURLList containsObject:urlStr]) {
                [globalURLList addObject:urlStr];
            }
        }
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(id)completionHandler {
    if (isRadarActive && url) {
        NSString *urlStr = url.absoluteString;
        if ([urlStr hasPrefix:@"http"] && ![urlStr containsString:@".jpg"] && ![urlStr containsString:@".png"]) {
            if (!globalURLList) globalURLList = [NSMutableArray array];
            if (![globalURLList containsObject:urlStr]) {
                [globalURLList addObject:urlStr];
            }
        }
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (isRadarActive && request.URL) {
        NSString *urlStr = request.URL.absoluteString;
        if ([urlStr hasPrefix:@"http"] && ![urlStr containsString:@".jpg"] && ![urlStr containsString:@".png"]) {
            if (!globalURLList) globalURLList = [NSMutableArray array];
            if (![globalURLList containsObject:urlStr]) {
                [globalURLList addObject:urlStr];
            }
        }
    }
    return %orig;
}

%end


// ====== 2. 注入雷达控制开关 ======
@interface ZZListingAprilViewController : UIViewController
@end

%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    globalVC = self;
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2;
    twoFingerLongPress.minimumPressDuration = 1.0;
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        globalVC = self;
        
        // 如果雷达已经在运行，则关闭雷达并导出 URL 列表
        if (isRadarActive) {
            isRadarActive = NO;
            NSString *result = [globalURLList componentsJoinedByString:@"\n\n"];
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎯 抓包完成！" 
                message:result.length > 0 ? @"已成功拦截该手机请求的所有隐藏 API，请复制发给开发者！" : @"没有抓到任何API" 
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addAction:[UIAlertAction actionWithTitle:@"一键复制并关闭" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                if (result.length > 0) {
                    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                    pasteboard.string = result;
                }
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }

        // 启动雷达
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"启动终极抓包雷达" 
                                                                       message:@"操作步骤：\n1. 点击下方【启动雷达】\n2. 手动点进那台有 15.4 的验机手机\n3. 等详情页加载完，再次【双指长按屏幕】，提取隐藏 API" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"启动雷达" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            isRadarActive = YES;
            globalURLList = [NSMutableArray array]; // 清空上次的记录
            
            UIAlertController *toast = [UIAlertController alertControllerWithTitle:@"📡 雷达已启动" message:@"现在请手动点击进入那台手机详情页！等它加载完，再双指长按屏幕！" preferredStyle:UIAlertControllerStyleAlert];
            [toast addAction:[UIAlertAction actionWithTitle:@"去点击" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:toast animated:YES completion:nil];
        }];
        
        [alert addAction:confirmAction];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

%end
