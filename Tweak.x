#import <UIKit/UIKit.h>

// ====== 消除 ARC 警告 ======
@interface NSObject (ZZModelToJSON)
- (id)mj_keyValues;
@end

// ====== 声明转转的网络类 ======
@interface ZZInfoDetailRequestModel : NSObject
@end

@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) id firstPageResponseData;
- (void)loadData;
- (void)reloadListingGoodsWithRespModel:(id)arg;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (NSString *)custom_extractInfoId:(id)obj;
- (NSString *)custom_dumpObject:(id)obj;
- (void)custom_reloadCollectionView;
@end

%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 注入双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2;
    twoFingerLongPress.minimumPressDuration = 1.0;
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本核弹级检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(将提取底层原生 JSON 进行暴力检索与诊断)" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"输入版本号 (如: 15.4、16)";
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"开始筛选" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
    if (!self.firstPageResponseData || ![self.firstPageResponseData respondsToSelector:NSSelectorFromString(@"infos")]) {
        return;
    }
    
    NSArray *infos = [self.firstPageResponseData valueForKey:@"infos"];
    if (!infos || infos.count == 0) return;
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取与分析" 
                                                                          message:@"后台正在并发拉取商品，并进行 JSON 显形透视..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 强引用代理对象，保活
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    __block int matchCount = 0;
    __block int reqSuccessCount = 0;
    __block int reqFailCount = 0;
    __block NSString *sampleServerResponse = @""; // 捕获服务器返回数据，用于终极诊断
    
    // 清理输入的目标版本号 (转全小写 + 去空格)
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    Class ReqModelClass = NSClassFromString(@"ZZInfoDetailRequestModel");
    
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length < 4) continue;
        
        id reqModel = [[ReqModelClass alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"];
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        Class ProxyClass = NSClassFromString(@"ZZGoodsDetailProxy");
        if (ProxyClass) {
            dispatch_group_enter(group);
            id proxy = [[ProxyClass alloc] init];
            [retainedProxies addObject:proxy]; 
            
            if ([proxy respondsToSelector:NSSelectorFromString(@"requestGoodsDetailDateWithRequestModel:success:failure:")]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [proxy performSelector:NSSelectorFromString(@"requestGoodsDetailDateWithRequestModel:success:failure:") withObject:reqModel withObject:^(id response) {
                    
                    [lock lock];
                    reqSuccessCount++;
                    [lock unlock];
                    
                    // ====== 核心突破：将任何类型的 response 强行剥壳转为字符串 ======
                    NSString *dumpStr = [self custom_dumpObject:response];
                    
                    // 记录第一条返回的数据用于调试诊断
                    [lock lock];
                    if (sampleServerResponse.length == 0) {
                        NSString *typeStr = NSStringFromClass([response class]);
                        sampleServerResponse = [NSString stringWithFormat:@"类型: %@\n数据: %@", typeStr, dumpStr];
                        if (sampleServerResponse.length > 400) {
                            sampleServerResponse = [sampleServerResponse substringToIndex:400]; // 截断防止弹窗太长
                        }
                    }
                    [lock unlock];
                    
                    // 进行文本核对
                    if (dumpStr && dumpStr.length > 0) {
                        NSString *cleanJson = [[dumpStr lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                        if ([cleanJson containsString:target]) {
                            [lock lock];
                            [matchedInfoIds addObject:infoId];
                            matchCount++;
                            [lock unlock];
                        }
                    }
                    
                    dispatch_group_leave(group);
                } /* 伪造 failure block 解决参数传递 */ ];
                // 为了避免 ARC 和多参数 performSelector 崩溃，实际开发中更安全的调用：
                // [proxy requestGoodsDetailDateWithRequestModel:reqModel success:^{...} failure:^{...}]
                // 注意：因为 Theos 里面我们已经暴露了声明，所以直接调用：
                #pragma clang diagnostic pop
            } else {
                dispatch_group_leave(group);
            }
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            [retainedProxies removeAllObjects];
            
            if (matchCount > 0) {
                NSMutableArray *filteredInfos = [NSMutableArray array];
                for (id item in infos) {
                    NSString *infoId = [weakSelf custom_extractInfoId:item];
                    if (infoId && [matchedInfoIds containsObject:infoId]) {
                        [filteredInfos addObject:item];
                    }
                }
                
                [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                
                if ([weakSelf respondsToSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:")]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [weakSelf performSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:") withObject:weakSelf.firstPageResponseData];
                    #pragma clang diagnostic pop
                } else {
                    [weakSelf custom_reloadCollectionView];
                }
                
                NSString *resultMsg = [NSString stringWithFormat:@"请求发出: %lu 个\n成功返回: %d 个\n匹配命中: %d 个", (unsigned long)infos.count, reqSuccessCount, matchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                // ====== 终极显形诊断弹窗 ======
                NSString *resultMsg = [NSString stringWithFormat:@"请求返回: %d个\n命中: 0个\n\n【服务器真实返回内容】:\n%@", reqSuccessCount, sampleServerResponse.length > 0 ? sampleServerResponse : @"无数据(提取失败)"];
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 终极对象剥壳器 (专治各种网络框架封装) ======
%new
- (NSString *)custom_dumpObject:(id)obj {
    if (!obj) return @"(nil)";
    @try {
        // 1. 数组或字典直接 description (最完美的原生 JSON 呈现)
        if ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) {
            return [obj description];
        }
        
        // 2. 检查是不是网络请求基类对象 (YTKBaseRequest / ZZBaseHTTPRequest)
        if ([obj respondsToSelector:NSSelectorFromString(@"responseJSONObject")]) {
            id jsonObj = [obj valueForKey:@"responseJSONObject"];
            if (jsonObj) return [jsonObj description];
        }
        if ([obj respondsToSelector:NSSelectorFromString(@"responseString")]) {
            id strObj = [obj valueForKey:@"responseString"];
            if (strObj) return [strObj description];
        }
        
        // 3. 检查是不是 ZZGoodsDetailModel，提取 respData 或 data
        if ([obj respondsToSelector:NSSelectorFromString(@"respData")]) {
            id dataObj = [obj valueForKey:@"respData"];
            if (dataObj) return [self custom_dumpObject:dataObj]; // 递归剥壳
        }
        
        // 4. 利用转转自带的 mj_keyValues 转成字典打印
        if ([obj respondsToSelector:NSSelectorFromString(@"mj_keyValues")]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id dict = [obj performSelector:NSSelectorFromString(@"mj_keyValues")];
            #pragma clang diagnostic pop
            if (dict) return [dict description];
        }
    } @catch (NSException *e) {}
    
    // 5. 终极兜底：直接返回对象的默认描述
    return [obj description];
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
