#import <UIKit/UIKit.h>

// 1. 声明网络请求模型
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@property (nonatomic) unsigned long long from;
@property (copy, nonatomic) NSString *pageType;
@end

// 2. 声明转转真实详情网络请求代理类
@interface ZZInfoDetailProxy : NSObject
- (void)requestInfoDetailDatas:(id)req success:(void(^)(id response))succ failure:(void(^)(id error))fail;
@end

// 3. 声明响应体，用于替换深层数据
@interface ZZListingResponseModel : NSObject
@property (retain, nonatomic) NSMutableArray *infos;
@end

// 4. 声明转转的列表控制器
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
@property (retain, nonatomic) ZZListingResponseModel *firstPageResponseData;
- (void)loadData;
- (void)real_reloadData:(id)arg;
- (void)reloadListingGoodsWithRespModel:(id)arg; // 触发 ZZFLEX 引擎重绘的核心方法

// 自定义注入的方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (void)custom_reloadCollectionView;
@end


%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 给当前 Controller 的 View 添加双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2; // 双指
    twoFingerLongPress.minimumPressDuration = 1.0;  // 长按 1 秒
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    // 仅在手势刚识别时触发一次
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本深层筛选" 
                                                                       message:@"请输入想筛选的iOS版本\n(将在后台并发拉取本页所有商品的详情进行精确匹配)" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"输入 iOS 版本号 (如: 15.4)";
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"开始静默筛选" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
    // 1. 多重保障：获取当前列表数据源
    NSArray *currentData = self.dataArray;
    if (!currentData || currentData.count == 0) {
        if (self.firstPageResponseData) {
            @try { currentData = [self.firstPageResponseData valueForKey:@"infos"]; } @catch(NSException*e){}
        }
    }
    
    if (!currentData || currentData.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"当前列表没有数据，请刷新或向下滑动后再试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    // 2. 弹出 Loading 提示框，拦截用户操作
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取详情..." 
                                                                          message:@"后台正在并发拉取当前页所有商品的深层参数\n请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    // 3. 初始化并发调度组和线程锁
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 4. 遍历当前商品，并发起真实详情网络请求
    for (id item in currentData) {
        NSString *infoId = nil;
        @try { 
            // 兼容 infoId 可能是 NSNumber 或 NSString 的情况
            id val = [item valueForKey:@"infoId"];
            if ([val isKindOfClass:[NSNumber class]]) {
                infoId = [(NSNumber *)val stringValue];
            } else if ([val isKindOfClass:[NSString class]]) {
                infoId = val;
            }
        } @catch (NSException *e) {}
        
        if (!infoId || infoId.length == 0) {
            continue;
        }
        
        // 进入并发组
        dispatch_group_enter(group);
        
        // 构造转转真实的详情请求体
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        reqModel.infoID = infoId;
        reqModel.from = 1;         // 模拟正常调用的参数
        reqModel.pageType = @"1";
        
        // 调用转转的真实网络代理发起请求
        ZZInfoDetailProxy *proxy = [[NSClassFromString(@"ZZInfoDetailProxy") alloc] init];
        [proxy requestInfoDetailDatas:reqModel success:^(id response) {
            BOOL isMatch = NO;
            @try {
                // response 就是 ZZGoodsDetailModel
                // 方案A：深度解析 param 数组里面的参数 (ZZGoodsDetailParamModel)
                NSArray *params = [response valueForKey:@"param"];
                if ([params isKindOfClass:[NSArray class]]) {
                    for (id paramItem in params) {
                        NSString *paramValue = [paramItem valueForKey:@"paramValue"];
                        if ([paramValue isKindOfClass:[NSString class]] && [paramValue containsString:version]) {
                            isMatch = YES;
                            break;
                        }
                    }
                }
                
                // 方案B：参数数组里没找到？去标题、正文、卖家描述里兜底找
                if (!isMatch) {
                    NSArray *keysToCheck = @[@"title", @"content", @"titleAndContent", @"sellerDescription", @"extend", @"userInfoDesc"];
                    for (NSString *key in keysToCheck) {
                        NSString *val = [response valueForKey:key];
                        if ([val isKindOfClass:[NSString class]] && [val containsString:version]) {
                            isMatch = YES;
                            break;
                        }
                    }
                }
                
                // 方案C：终极兜底，强转对象的字符串描述
                if (!isMatch) {
                    NSString *fullDesc = [response description];
                    if ([fullDesc containsString:version]) {
                        isMatch = YES;
                    }
                }
            } @catch (NSException *e) {}
            
            // 如果成功匹配该版本，加入安全集合
            if (isMatch) {
                [lock lock];
                [matchedInfoIds addObject:infoId];
                [lock unlock];
            }
            
            // 离开并发组
            dispatch_group_leave(group);
            
        } failure:^(id error) {
            // 请求失败也要离开并发组，防止死锁
            dispatch_group_leave(group);
        }];
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 5. 等待所有并发的网络请求拉取完毕
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            // 按原始列表顺序过滤商品
            NSMutableArray *sortedFilteredArray = [NSMutableArray array];
            for (id item in currentData) {
                NSString *infoId = nil;
                @try { 
                    id val = [item valueForKey:@"infoId"];
                    if ([val isKindOfClass:[NSNumber class]]) infoId = [val stringValue];
                    else if ([val isKindOfClass:[NSString class]]) infoId = val;
                } @catch (NSException *e) {}
                
                if (infoId && [matchedInfoIds containsObject:infoId]) {
                    [sortedFilteredArray addObject:item];
                }
            }
            
            if (sortedFilteredArray.count > 0) {
                // 替换列表的数据源
                weakSelf.dataArray = [sortedFilteredArray copy];
                
                // 因为转转使用的是 ZZFLEX 布局，必须深度替换 firstPageResponseData 中的数据
                if (weakSelf.firstPageResponseData) {
                    @try {
                        [weakSelf.firstPageResponseData setValue:[sortedFilteredArray mutableCopy] forKey:@"infos"];
                    } @catch (NSException *e) {}
                }
                
                // 调用转转官方的方法，触发 ZZFLEX 引擎重构整个 UI 列表！
                if ([weakSelf respondsToSelector:@selector(reloadListingGoodsWithRespModel:)]) {
                    [weakSelf performSelector:@selector(reloadListingGoodsWithRespModel:) withObject:weakSelf.firstPageResponseData];
                } else if ([weakSelf respondsToSelector:@selector(real_reloadData:)]) {
                    [weakSelf performSelector:@selector(real_reloadData:) withObject:nil];
                } else {
                    [weakSelf custom_reloadCollectionView]; // 兜底
                }
            } else {
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"筛选结果为空" 
                                                                                    message:@"刚才拉取了本页所有的商品详情，但均未发现该系统版本。\n请往下滑动加载下一页数据后，再次双指长按进行筛选。" 
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// 兜底刷新视图方法
%new
- (void)custom_reloadCollectionView {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:self.view];
    while (queue.count > 0) {
        UIView *currentView = queue.firstObject;
        [queue removeObjectAtIndex:0];
        
        if ([currentView isKindOfClass:[UICollectionView class]]) {
            [(UICollectionView *)currentView reloadData];
        } else if ([currentView isKindOfClass:[UITableView class]]) {
            [(UITableView *)currentView reloadData];
        }
        
        [queue addObjectsFromArray:currentView.subviews];
    }
}

%end
