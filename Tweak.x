#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ====== 全局变量 ======
static NSMutableURLRequest *globalLegoRequest = nil;
static NSString *globalLegoOriginalInfoId = nil;

// ====== 1. 偷天换日：在极底层网卡拦截并保存合法的 Lego 请求模板 ======
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(id)completionHandler {
    NSString *urlStr = request.URL.absoluteString;
    // 只要是请求了 lego 接口，立刻实施偷窃
    if ([urlStr containsString:@"lego.zhuanzhuan.com/v1/coke"]) {
        NSString *bodyStr = nil;
        if (request.HTTPBody) {
            bodyStr = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        }
        
        NSString *searchArea = [NSString stringWithFormat:@"%@ || %@", urlStr, bodyStr ?: @""];
        // 匹配 18 或 19 位的数字商品 ID
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(1|2)\\d{17,18}" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:searchArea options:0 range:NSMakeRange(0, searchArea.length)];
        
        // 保存包含通行证的请求模板和被点击的商品 ID
        if (match) {
            globalLegoOriginalInfoId = [searchArea substringWithRange:match.range];
            globalLegoRequest = [request mutableCopy];
        }
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSString *urlStr = request.URL.absoluteString;
    if ([urlStr containsString:@"lego.zhuanzhuan.com/v1/coke"]) {
        NSString *bodyStr = nil;
        if (request.HTTPBody) {
            bodyStr = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        }
        
        NSString *searchArea = [NSString stringWithFormat:@"%@ || %@", urlStr, bodyStr ?: @""];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(1|2)\\d{17,18}" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:searchArea options:0 range:NSMakeRange(0, searchArea.length)];
        
        if (match) {
            globalLegoOriginalInfoId = [searchArea substringWithRange:match.range];
            globalLegoRequest = [request mutableCopy];
        }
    }
    return %orig;
}

%end


// ====== 2. 列表控制器与克隆轰炸逻辑 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) id firstPageResponseData;
- (void)loadData;
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (void)custom_collectProductsFrom:(id)obj into:(NSMutableDictionary *)dict;
- (NSString *)custom_extractInfoId:(id)obj;
- (void)custom_pruneZZFLEXArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds kept:(int *)kept removed:(int *)removed;
- (void)custom_reloadCollectionView;
@end

%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2;
    twoFingerLongPress.minimumPressDuration = 1.0;
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本克隆检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(已挂载底层请求偷取与无限克隆分身引擎)" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"输入版本号 (如: 15.4、16)";
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"克隆并轰炸" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *versionText = alert.textFields.firstObject.text;
            if (versionText.length > 0) {
                [weakSelf custom_filterWithVersion:versionText];
            }
        }];
        
        UIAlertAction *resetAction = [UIAlertAction actionWithTitle:@"重置列表" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            if ([weakSelf respondsToSelector:@selector(loadData)]) {
                [weakSelf performSelector:@selector(loadData)];
            }
        }];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
        
        [alert addAction:confirmAction];
        [alert addAction:resetAction];
        [alert addAction:cancelAction];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

%new
- (void)custom_filterWithVersion:(NSString *)version {
    if (!self.dataArray || self.dataArray.count == 0) return;
    
    NSMutableDictionary *allProducts = [NSMutableDictionary dictionary];
    [self custom_collectProductsFrom:self.dataArray into:allProducts];
    if (allProducts.count == 0) return;

    // 关键拦截校验：必须有模板才能执行克隆！
    if (!globalLegoRequest || !globalLegoOriginalInfoId) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚠️ 缺少合法请求通行证" 
                                                                       message:@"系统尚未捕获到合法的验机请求。\n\n请先手动点击进入任意一台【验机手机】的详情页！\n\n等详情页加载完成后，再退回这个列表，执行双指长按即可！" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"去点一台" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在执行克隆扫描" 
                                                                          message:[NSString stringWithFormat:@"已锁定 %lu 台设备\n正在伪装 App 绕过鉴权提取 Lego 数据...", (unsigned long)allProducts.count]
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];

    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    __block int httpApiCount = 0;
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    for (NSString *infoId in allProducts.allKeys) {
        
        // ====== 核心：深拷贝全局合法的请求模板 ======
        NSMutableURLRequest *newReq = [globalLegoRequest mutableCopy];
        
        // 1. 替换 URL 中的旧 ID 为新 ID
        NSString *newUrlStr = [newReq.URL.absoluteString stringByReplacingOccurrencesOfString:globalLegoOriginalInfoId withString:infoId];
        newReq.URL = [NSURL URLWithString:newUrlStr];
        
        // 2. 替换 Body 中的旧 ID 为新 ID
        if (newReq.HTTPBody) {
            NSString *bodyStr = [[NSString alloc] initWithData:newReq.HTTPBody encoding:NSUTF8StringEncoding];
            NSString *newBodyStr = [bodyStr stringByReplacingOccurrencesOfString:globalLegoOriginalInfoId withString:infoId];
            newReq.HTTPBody = [newBodyStr dataUsingEncoding:NSUTF8StringEncoding];
        }
        
        // 3. 替换 Header 中的旧 ID (如果有)
        NSMutableDictionary *newHeaders = [newReq.allHTTPHeaderFields mutableCopy];
        for (NSString *key in newHeaders.allKeys) {
            NSString *val = newHeaders[key];
            if ([val containsString:globalLegoOriginalInfoId]) {
                newHeaders[key] = [val stringByReplacingOccurrencesOfString:globalLegoOriginalInfoId withString:infoId];
            }
        }
        newReq.allHTTPHeaderFields = newHeaders;
        
        // 发送带合法 Token 的克隆请求
        dispatch_group_enter(group);
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:newReq completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
            [lock lock]; httpApiCount++; [lock unlock];
            
            if (data) {
                NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (json) {
                    NSString *unicodeDecoded = [NSString stringWithCString:[json cStringUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding];
                    if (unicodeDecoded) json = unicodeDecoded;
                    
                    NSString *cleanJson = [[json lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                    
                    // 精准击杀！
                    if ([cleanJson containsString:target]) {
                        [lock lock];
                        [matchedInfoIds addObject:infoId];
                        [lock unlock];
                    }
                }
            }
            dispatch_group_leave(group);
        }];
        [task resume];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            if (matchedInfoIds.count > 0) {
                int kept = 0, removed = 0;
                NSMutableArray *mutDataArray = [weakSelf.dataArray mutableCopy];
                [weakSelf custom_pruneZZFLEXArray:mutDataArray matchedIds:matchedInfoIds kept:&kept removed:&removed];
                weakSelf.dataArray = mutDataArray;
                
                if (weakSelf.firstPageResponseData) {
                    @try {
                        NSArray *infos = [weakSelf.firstPageResponseData valueForKey:@"infos"];
                        NSMutableArray *filteredInfos = [NSMutableArray array];
                        for (id item in infos) {
                            NSString *iId = [weakSelf custom_extractInfoId:item];
                            if (iId && [matchedInfoIds containsObject:iId]) {
                                [filteredInfos addObject:item];
                            }
                        }
                        [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                    } @catch(...) {}
                }
                
                [weakSelf custom_reloadCollectionView];
                
                NSString *resultMsg = [NSString stringWithFormat:@"总计处理设备: %lu 台\n克隆请求并成功接收: %d 次\n\n精准命中并保留设备: %lu 台！\n成功剔除 %d 台无关设备。", (unsigned long)allProducts.count, httpApiCount, (unsigned long)matchedInfoIds.count, removed];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美绝杀" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                NSString *resultMsg = [NSString stringWithFormat:@"已克隆检索设备: %lu 台\n成功接收数据: %d 次\n\n最终匹配命中: 0 台\n\n※ 请继续向下加载更多设备后，再次重试！", (unsigned long)allProducts.count, httpApiCount];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"当前列表无匹配项" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 递归提取列表中的所有商品 ======
%new
- (void)custom_collectProductsFrom:(id)obj into:(NSMutableDictionary *)dict {
    if (!obj) return;
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) [self custom_collectProductsFrom:item into:dict];
        return;
    }
    if ([obj respondsToSelector:NSSelectorFromString(@"itemsArray")]) {
        @try { id items = [obj valueForKey:@"itemsArray"]; [self custom_collectProductsFrom:items into:dict]; } @catch(...) {}
        return;
    }
    id realData = obj;
    if ([obj respondsToSelector:NSSelectorFromString(@"dataModel")]) {
        id inner = [obj valueForKey:@"dataModel"];
        if (inner) realData = inner;
    }
    NSString *infoId = [self custom_extractInfoId:realData];
    if (infoId && infoId.length > 4) dict[infoId] = realData;
}

// ====== 原地修剪 UI 列表 ======
%new
- (void)custom_pruneZZFLEXArray:(NSMutableArray *)array matchedIds:(NSSet *)matchedIds kept:(int *)kept removed:(int *)removed {
    for (NSInteger i = array.count - 1; i >= 0; i--) {
        id item = array[i];
        if ([item respondsToSelector:NSSelectorFromString(@"itemsArray")]) {
            @try {
                id items = [item valueForKey:@"itemsArray"];
                if ([items isKindOfClass:[NSMutableArray class]]) {
                    [self custom_pruneZZFLEXArray:items matchedIds:matchedIds kept:kept removed:removed];
                } else if ([items isKindOfClass:[NSArray class]]) {
                    NSMutableArray *mut = [items mutableCopy];
                    [self custom_pruneZZFLEXArray:mut matchedIds:matchedIds kept:kept removed:removed];
                    [item setValue:mut forKey:@"itemsArray"];
                }
            } @catch(...) {}
            continue;
        }
        if ([item isKindOfClass:[NSMutableArray class]]) {
            [self custom_pruneZZFLEXArray:item matchedIds:matchedIds kept:kept removed:removed];
            continue;
        }
        id realData = item;
        if ([item respondsToSelector:NSSelectorFromString(@"dataModel")]) {
            id inner = [item valueForKey:@"dataModel"];
            if (inner) realData = inner;
        }
        NSString *infoId = [self custom_extractInfoId:realData];
        if (infoId && infoId.length > 4) {
            if ([matchedIds containsObject:infoId]) (*kept)++;
            else { [array removeObjectAtIndex:i]; (*removed)++; }
        }
    }
}

// ====== 智能提取商品 ID ======
%new
- (NSString *)custom_extractInfoId:(id)obj {
    if (!obj) return nil;
    @try {
        if ([obj respondsToSelector:NSSelectorFromString(@"infoId")]) {
            id val = [obj valueForKey:@"infoId"];
            if ([val isKindOfClass:[NSString class]]) return val;
            if ([val isKindOfClass:[NSNumber class]]) return [(NSNumber *)val stringValue];
        }
        if ([obj respondsToSelector:NSSelectorFromString(@"infoID")]) {
            id val = [obj valueForKey:@"infoID"];
            if ([val isKindOfClass:[NSString class]]) return val;
            if ([val isKindOfClass:[NSNumber class]]) return [(NSNumber *)val stringValue];
        }
        NSArray *wrappers = @[@"dataModel", @"feedModel", @"itemModel", @"searchResult"];
        for (NSString *key in wrappers) {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id inner = [obj valueForKey:key];
                if (inner && inner != obj) return [self custom_extractInfoId:inner];
            }
        }
    } @catch(...) {}
    return nil;
}

// 暴力刷新视图
%new
- (void)custom_reloadCollectionView {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:self.view];
    while (queue.count > 0) {
        UIView *currentView = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([currentView isKindOfClass:[UICollectionView class]]) [(UICollectionView *)currentView reloadData];
        else if ([currentView isKindOfClass:[UITableView class]]) [(UITableView *)currentView reloadData];
        [queue addObjectsFromArray:currentView.subviews];
    }
}

%end
