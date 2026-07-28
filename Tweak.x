#import <UIKit/UIKit.h>

// ====== 1. 声明转转的网络请求类 ======
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)req success:(void(^)(id response))success failure:(void(^)(id error))failure;
@end

@interface ZZListingResponseModel : NSObject
@property (retain, nonatomic) NSMutableArray *infos;
@end

// ====== 2. 声明列表控制器 ======
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) ZZListingResponseModel *firstPageResponseData;
- (void)loadData;

// 自定义方法声明
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterWithVersion:(NSString *)version;
- (NSString *)custom_extractInfoId:(id)obj;
- (void)custom_reloadCollectionView;
@end


%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 注入双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2; // 双指
    twoFingerLongPress.minimumPressDuration = 1.0;  // 长按 1 秒
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本究极检索" 
                                                                       message:@"请输入想筛选的iOS版本\n(启用强驻留并发请求及硬核数据透视)" 
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
    // 1. 直击转转的底层商品数据源，避开外层排版壳
    if (!self.firstPageResponseData || ![self.firstPageResponseData respondsToSelector:NSSelectorFromString(@"infos")]) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"获取失败" message:@"找不到底层商品数据，请向下浏览一页或刷新后再试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    NSArray *infos = [self.firstPageResponseData valueForKey:@"infos"];
    if (!infos || infos.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"列表暂无数据，请刷新后重试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默并发拉取" 
                                                                          message:@"后台正在处理当前页所有商品，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // ====== 绝对核心：强引用代理对象，防止 ARC 将其提早销毁 ======
    NSMutableArray *retainedProxies = [NSMutableArray array];
    
    // 数据监控指标
    __block int reqSuccessCount = 0;
    __block int reqFailCount = 0;
    __block int proxyErrorCount = 0;
    __block int matchCount = 0;
    
    // 清理输入的目标版本号 (转全小写 + 去空格)
    NSString *target = [[version lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    Class ReqModelClass = NSClassFromString(@"ZZInfoDetailRequestModel");
    Class ProxyClass = NSClassFromString(@"ZZInfoDetailProxy");
    
    for (id item in infos) {
        NSString *infoId = [self custom_extractInfoId:item];
        if (!infoId || infoId.length < 4) continue;

        if (!ReqModelClass || !ProxyClass) {
            proxyErrorCount++;
            continue;
        }
        
        dispatch_group_enter(group);
        
        // 构造请求体
        id reqModel = [[ReqModelClass alloc] init];
        [reqModel setValue:infoId forKey:@"infoID"];
        [reqModel setValue:@(1) forKey:@"from"];
        [reqModel setValue:@"1" forKey:@"pageType"];
        
        id proxy = [[ProxyClass alloc] init];
        [retainedProxies addObject:proxy]; // 必须强引用！
        
        if ([proxy respondsToSelector:@selector(requestInfoDetailDatas:success:failure:)]) {
            [proxy requestInfoDetailDatas:reqModel success:^(id response) {
                [lock lock];
                reqSuccessCount++;
                [lock unlock];
                
                BOOL isMatch = NO;
                @try {
                    // 安全解析 1：提取验机详情里的参数 (param 数组)
                    NSArray *params = [response valueForKey:@"param"];
                    if ([params isKindOfClass:[NSArray class]]) {
                        for (id pItem in params) {
                            id pVal = [pItem valueForKey:@"paramValue"];
                            if ([pVal isKindOfClass:[NSString class]]) {
                                NSString *cleanVal = [[(NSString *)pVal lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                                if ([cleanVal containsString:target]) {
                                    isMatch = YES;
                                    break;
                                }
                            }
                        }
                    }
                    
                    // 安全解析 2：如果参数里没有，去标题、介绍和卖家描述里搜
                    if (!isMatch) {
                        NSArray *safeKeys = @[@"title", @"content", @"sellerDescription", @"extendJson"];
                        for (NSString *key in safeKeys) {
                            id val = [response valueForKey:key];
                            if ([val isKindOfClass:[NSString class]]) {
                                NSString *cleanVal = [[(NSString *)val lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
                                if ([cleanVal containsString:target]) {
                                    isMatch = YES;
                                    break;
                                }
                            }
                        }
                    }
                } @catch (...) {}
                
                if (isMatch) {
                    [lock lock];
                    [matchedInfoIds addObject:infoId];
                    matchCount++;
                    [lock unlock];
                }
                dispatch_group_leave(group);
                
            } failure:^(id error) {
                [lock lock];
                reqFailCount++;
                [lock unlock];
                dispatch_group_leave(group);
            }];
        } else {
            [lock lock];
            proxyErrorCount++;
            [lock unlock];
            dispatch_group_leave(group);
        }
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 5. 等待所有并发网络请求完成
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            // 安全释放网络请求对象
            [retainedProxies removeAllObjects];
            
            NSString *statusMsg = [NSString stringWithFormat:@"发出了 %lu 个请求\n成功返回: %d 个\n失败: %d 个\n代理异常: %d 个\n匹配命中: %d 个", 
                                   (unsigned long)infos.count, reqSuccessCount, reqFailCount, proxyErrorCount, matchCount];
                                   
            if (matchCount > 0) {
                // 筛选命中项
                NSMutableArray *filteredInfos = [NSMutableArray array];
                for (id item in infos) {
                    NSString *infoId = [weakSelf custom_extractInfoId:item];
                    if (infoId && [matchedInfoIds containsObject:infoId]) {
                        [filteredInfos addObject:item];
                    }
                }
                
                // 替换掉转转底层的数据源
                [weakSelf.firstPageResponseData setValue:filteredInfos forKey:@"infos"];
                
                // 强制 ZZFLEX 布局引擎重绘
                if ([weakSelf respondsToSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:")]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [weakSelf performSelector:NSSelectorFromString(@"reloadListingGoodsWithRespModel:") withObject:weakSelf.firstPageResponseData];
                    #pragma clang diagnostic pop
                } else {
                    [weakSelf custom_reloadCollectionView]; // 兜底刷新
                }
                
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"筛选成功" message:statusMsg preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"完美" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:successAlert animated:YES completion:nil];
                
            } else {
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"未找到匹配的商品" message:statusMsg preferredStyle:UIAlertControllerStyleAlert];
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
        // 如果数据被包装壳包裹，智能钻取
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
