#import <UIKit/UIKit.h>

// 1. 声明网络请求模型
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

// 2. 声明真实详情网络请求代理类
@interface ZZGoodsDetailProxy : NSObject
- (void)requestGoodsDetailDateWithRequestModel:(id)a0 success:(void(^)(id response))a1 failure:(void(^)(id error))a2;
@end

// 3. 声明响应体数据模型
@interface ZZListingResponseModel : NSObject
@property (retain, nonatomic) NSMutableArray *infos;
@end

// 4. 声明转转的列表控制器
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) ZZListingResponseModel *firstPageResponseData;
- (void)loadData;

// 自定义方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (BOOL)custom_safeMatchObject:(id)obj target:(NSString *)target;
- (NSString *)custom_extractInfoId:(id)obj;
@end

%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 注入双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2; // 需要双指
    twoFingerLongPress.minimumPressDuration = 1.0;  // 长按 1 秒
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本深度筛选" 
                                                                       message:@"请输入想筛选的iOS版本\n(全安全模式：精准提取深层参数，杜绝闪退)" 
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
                [weakSelf custom_fetchDetailAndFilterWithVersion:versionText];
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
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version {
    // 1. 直击最底层数据，避开 ZZFLEX 分组包装壳
    if (!self.firstPageResponseData || ![self.firstPageResponseData respondsToSelector:NSSelectorFromString(@"infos")]) {
        return;
    }
    NSArray *infos = [self.firstPageResponseData valueForKey:@"infos"];
    if (!infos || infos.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"列表暂无数据，请向下滑动加载或刷新后再试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取与分析..." 
                                                                          message:@"正在安全提取底层参数，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    __block int localMatchCount = 0;
    __block int netMatchCount = 0;
    
    // 对输入的版本号进行标准化处理（去空格 + 全小写），比如 "15.4"
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length == 0) continue;

        // ====== 阶段一：本地绝对安全匹配 ======
        if ([self custom_safeMatchObject:item target:target]) {
            [lock lock];
            [matchedInfoIds addObject:infoId];
            localMatchCount++;
            [lock unlock];
            continue; // 本地找到了，极速跳过网络请求！
        }

        // ====== 阶段二：网络详情并发拉取 ======
        dispatch_group_enter(group);
        
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        reqModel.infoID = infoId;
        reqModel.from = 1; 
        reqModel.pageType = @"1";
        
        id proxy = [[NSClassFromString(@"ZZGoodsDetailProxy") alloc] init];
        if ([proxy respondsToSelector:NSSelectorFromString(@"requestGoodsDetailDateWithRequestModel:success:failure:")]) {
            [proxy requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
                // 安全解析拉取回来的详情模型
                if ([self custom_safeMatchObject:response target:target]) {
                    [lock lock];
                    [matchedInfoIds addObject:infoId];
                    netMatchCount++;
                    [lock unlock];
                }
                dispatch_group_leave(group);
            } failure:^(id error) {
                dispatch_group_leave(group);
            }];
        } else {
            dispatch_group_leave(group);
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 5. 等待所有并发请求拉取完毕
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            // 组装结果
            NSMutableArray *filteredInfos = [NSMutableArray array];
            for (id item in infos) {
                NSString *infoId = [weakSelf custom_extractInfoId:item];
                if (infoId && [matchedInfoIds containsObject:infoId]) {
                    [filteredInfos addObject:item];
                }
            }
            
            if (filteredInfos.count > 0) {
                // 彻底替换转转的底层数据源
                [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                
                // 消除 ARC 警告，安全调用原生刷新方法
                if ([weakSelf respondsToSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:")]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [weakSelf performSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:") withObject:weakSelf.firstPageResponseData];
                    #pragma clang diagnostic pop
                }
                
                NSString *resultMsg = [NSString stringWithFormat:@"列表提取成功: %d 条\n底层网络拉取: %d 条", localMatchCount, netMatchCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选完成" message:resultMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未能筛到相关商品" 
                                                                                    message:@"深层安全扫描了本页所有商品及详情参数\n未发现该系统版本！请下拉加载下一页。"
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
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
        // 如果数据被包装，安全剥开
        if ([obj respondsToSelector:NSSelectorFromString(@"dataModel")]) {
            id inner = [obj valueForKey:@"dataModel"];
            if (inner && inner != obj) return [self custom_extractInfoId:inner];
        }
        if ([obj respondsToSelector:NSSelectorFromString(@"feedModel")]) {
            id inner = [obj valueForKey:@"feedModel"];
            if (inner && inner != obj) return [self custom_extractInfoId:inner];
        }
    } @catch(NSException *e) {}
    return nil;
}

// ====== 绝对安全防闪退文本提取器 ======
%new
- (BOOL)custom_safeMatchObject:(id)obj target:(NSString *)target {
    if (!obj) return NO;
    
    // 1. 直取最可能含有文字的字段，避开任何对象转换
    NSArray *stringKeys = @[@"title", @"desc", @"content", @"sellerDescription", 
                            @"titleAndContent", @"extendJson", @"userInfoLabelText", 
                            @"userCateLabelDesc", @"priceDesc", @"subTitle", @"paramValue"];
                            
    for (NSString *key in stringKeys) {
        @try {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id val = [obj valueForKey:key];
                if ([val isKindOfClass:[NSString class]]) {
                    NSString *cleanVal = [[(NSString *)val lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                    if ([cleanVal containsString:target]) return YES;
                }
            }
        } @catch (NSException *e) {}
    }
    
    // 2. 单独安全解析参数数组 (ZZGoodsDetailModel -> param)
    @try {
        if ([obj respondsToSelector:NSSelectorFromString(@"param")]) {
            id paramArr = [obj valueForKey:@"param"];
            if ([paramArr isKindOfClass:[NSArray class]]) {
                for (id pItem in (NSArray *)paramArr) {
                    if ([pItem respondsToSelector:NSSelectorFromString(@"paramValue")]) {
                        id pVal = [pItem valueForKey:@"paramValue"];
                        if ([pVal isKindOfClass:[NSString class]]) {
                            NSString *cleanVal = [[(NSString *)pVal lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                            if ([cleanVal containsString:target]) return YES;
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    // 3. 安全解析嵌套模型 (避免递归无限循环)
    NSArray *wrapperKeys = @[@"dataModel", @"feedModel"];
    for (NSString *key in wrapperKeys) {
        @try {
            if ([obj respondsToSelector:NSSelectorFromString(key)]) {
                id innerObj = [obj valueForKey:key];
                if (innerObj && innerObj != obj) {
                    if ([self custom_safeMatchObject:innerObj target:target]) return YES;
                }
            }
        } @catch (NSException *e) {}
    }
    
    return NO;
}

%end
