#import <UIKit/UIKit.h>

static BOOL isRadarActive = NO;
static NSString *targetStr = @"";
static __weak UIViewController *globalVC = nil;

// ====== 1. 监听转转的底层核心网卡 ======
@interface ZZNetworkAgent : NSObject
- (void)handleRequestResult:(id)a0 responseObject:(id)a1 error:(id)a2;
@end

%hook ZZNetworkAgent

- (void)handleRequestResult:(id)request responseObject:(id)response error:(id)error {
    %orig;
    
    // 如果雷达没开启，或者没有返回数据，直接放行
    if (!isRadarActive || !response || targetStr.length == 0) return;
    
    // 开启异步线程窃听数据，绝不卡顿
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSString *jsonStr = nil;
            if ([response respondsToSelector:@selector(yy_modelToJSONObject)]) {
                jsonStr = [[response performSelector:@selector(yy_modelToJSONObject)] description];
            } else if ([response isKindOfClass:[NSDictionary class]] || [response isKindOfClass:[NSArray class]]) {
                NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
                if (data) jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            } else {
                jsonStr = [response description];
            }
            
            if (!jsonStr) return;
            
            // 强行解开 Unicode 乱码
            NSString *unicodeDecoded = [NSString stringWithCString:[jsonStr cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
            if (unicodeDecoded) jsonStr = unicodeDecoded;
            
            NSString *cleanStr = [[jsonStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
            
            // 🎯 核心：如果这个网络包里包含了 "15.4"！！！
            if ([cleanStr containsString:targetStr]) {
                isRadarActive = NO; // 抓到一次就关闭雷达，防止弹窗轰炸
                
                // 疯狂提取这个网络请求的 URL
                NSString *urlStr = @"无法提取URL，请联系开发者";
                if ([request isKindOfClass:[NSURLSessionTask class]]) {
                    urlStr = [[(NSURLSessionTask *)request currentRequest].URL absoluteString];
                } else if ([request respondsToSelector:NSSelectorFromString(@"url")]) {
                    urlStr = [[request valueForKey:@"url"] description];
                } else if ([request respondsToSelector:NSSelectorFromString(@"URLString")]) {
                    urlStr = [[request valueForKey:@"URLString"] description];
                } else if ([request respondsToSelector:NSSelectorFromString(@"request")]) {
                    id innerReq = [request valueForKey:@"request"];
                    if ([innerReq isKindOfClass:[NSURLRequest class]]) {
                        urlStr = [[(NSURLRequest *)innerReq URL] absoluteString];
                    }
                } else {
                    urlStr = [request description];
                }
                
                // 瞬间弹窗警报！
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (globalVC) {
                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎯 抓到隐藏API了！" 
                            message:[NSString stringWithFormat:@"成功拦截参数: %@\n\n吐出该数据的API接口是:\n%@\n\n兄弟，快把这个截图发给我！", targetStr, urlStr] 
                            preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"收到" style:UIAlertActionStyleCancel handler:nil]];
                        [globalVC presentViewController:alert animated:YES completion:nil];
                    }
                });
            }
        } @catch(...) {}
    });
}

%end


// ====== 2. 列表控制器注入雷达开关 ======
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开启隐藏API雷达" 
                                                                       message:@"1. 输入你想抓的系统(如15.4)\n2. 点击开启雷达\n3. 手动点进那台有15.4的手机\n4. 雷达会自动弹出它的隐藏接口" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"输入你想抓的参数 (如: 15.4)";
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        }];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"部署雷达" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            targetStr = [[alert.textFields.firstObject.text lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
            if (targetStr.length > 0) {
                isRadarActive = YES;
                
                UIAlertController *toast = [UIAlertController alertControllerWithTitle:@"📡 雷达已开启" message:@"现在请手动点击进入那台有 15.4 的手机详情页！" preferredStyle:UIAlertControllerStyleAlert];
                [toast addAction:[UIAlertAction actionWithTitle:@"去点击" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:toast animated:YES completion:nil];
            }
        }];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
        
        [alert addAction:confirmAction];
        [alert addAction:cancelAction];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

%end
