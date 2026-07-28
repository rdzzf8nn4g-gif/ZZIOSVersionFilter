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
- (void)real_reloadData:(id)arg;
- (void)reloadListingGoodsWithRespModel:(id)arg; // 触发 ZZFLEX 引擎重绘的核心方法

// 自定义注入的方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (BOOL)custom_isObject:(id)object matchTarget:(NSString *)target;
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
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本深度筛选" 
                                                                       message:@"请输入想筛选的iOS版本\n(将深度解析列表标签并在后台拉取详情)" 
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
    // 1. 获取当前列表数据源
    NSArray *currentData = self.dataArray;
    if (!currentData || currentData.count == 0) {
        if (self.firstPageResponseData) {
            @try { currentData = [self.firstPageResponseData valueForKey:@"infos"]; } @catch(NSException*e){}
        }
    }
    
    if (!currentData || currentData.count == 0) {
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"提示" message:@"列表暂无数据，请刷新后重试" preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
        return;
    }
    
    // 2. 弹出 Loading
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取与分析..." 
                                                                          message:@"后台正在处理当前页所有商品，请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    // 3. 初始化并发调度组和线程锁
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set];
    NSLock *lock = [[NSLock alloc] init];
    
    // 4. 遍历当前商品
    for (id item in currentData) {
        NSString *infoId = nil;
        @try { 
            // 兼容 infoId 类型
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

        // ====== 核心改进 1：先进行深度本地搜索 ======
        // 如果列表自带的标签、扩展字段里已经包含了版本号，直接跳过网络请求，极速处理！
        if ([self custom_isObject:item matchTarget:version]) {
            [lock lock];
            [matchedInfoIds addObject:infoId];
            [lock unlock];
            continue;
        }

        // ====== 核心改进 2：本地没搜到，再并发去网络拉详情页 ======
        dispatch_group_enter(group);
        
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        reqModel.infoID = infoId;
        reqModel.from = 1; 
        
        ZZGoodsDetailProxy *proxy = [[NSClassFromString(@"ZZGoodsDetailProxy") alloc] init];
        [proxy requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
            
            // 解析详情数据（也是用极深度的反解析方法）
            if ([self custom_isObject:response matchTarget:version]) {
                [lock lock];
                [matchedInfoIds addObject:infoId];
                [lock unlock];
            }
            dispatch_group_leave(group);
            
        } failure:^(id error) {
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
                    if ([val isKindOfClass:[NSNumber class]]) infoId = [(NSNumber *)val stringValue];
                    else if ([val isKindOfClass:[NSString class]]) infoId = val;
                } @catch (NSException *e) {}
                
                if (infoId && [matchedInfoIds containsObject:infoId]) {
                    [sortedFilteredArray addObject:item];
                }
            }
            
            if (sortedFilteredArray.count > 0) {
                // ====== 核心改进 3：深度替换并重载 ZZFLEX ======
                weakSelf.dataArray = [sortedFilteredArray copy];
                
                if (weakSelf.firstPageResponseData) {
                    @try {
                        [weakSelf.firstPageResponseData setValue:[sortedFilteredArray mutableCopy] forKey:@"infos"];
                    } @catch (NSException *e) {}
                }
                
                // 触发转转 ZZFLEX 布局引擎重绘
                if ([weakSelf respondsToSelector:@selector(reloadListingGoodsWithRespModel:)]) {
                    [weakSelf performSelector:@selector(reloadListingGoodsWithRespModel:) withObject:weakSelf.firstPageResponseData];
                } else if ([weakSelf respondsToSelector:@selector(real_reloadData:)]) {
                    [weakSelf performSelector:@selector(real_reloadData:) withObject:nil];
                } else {
                    [weakSelf custom_reloadCollectionView]; // 暴力兜底
                }
            } else {
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"筛选结果为空" 
                                                                                    message:@"深层遍历了列表与详情页，均未发现该系统版本。\n请下拉加载更多后重试。" 
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

// ====== 核心改进 4：全知全能的深层文本匹配引擎 ======
%new
- (BOOL)custom_isObject:(id)object matchTarget:(NSString *)target {
    if (!object || !target) return NO;
    
    @try {
        // 方法 A：尝试将其转为字典 (利用转转内嵌的 MJExtension 库)
        if ([object respondsToSelector:NSSelectorFromString(@"mj_keyValues")]) {
            id dict = [object performSelector:NSSelectorFromString(@"mj_keyValues")];
            if (dict && [[dict description] containsString:target]) {
                return YES;
            }
        }
        
        // 方法 B：尝试将其转为字典 (利用转转内嵌的 YYModel 库)
        if ([object respondsToSelector:NSSelectorFromString(@"yy_modelToJSONObject")]) {
            id dict = [object performSelector:NSSelectorFromString(@"yy_modelToJSONObject")];
            if (dict && [[dict description] containsString:target]) {
                return YES;
            }
        }
        
        // 方法 C：直接提取常见字段兜底
        NSArray *keys = @[@"title", @"desc", @"extendJson", @"userInfoLabelText", @"priceDesc", @"userCateLabelDesc", @"titleAndContent", @"sellerDescription"];
        for (NSString *key in keys) {
            id val = [object valueForKey:key];
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val containsString:target]) {
                return YES;
            }
        }
        
        // 方法 D：原始描述强转兜底
        if ([[object description] containsString:target]) {
            return YES;
        }
    } @catch(NSException *e) {}
    
    return NO;
}

// 暴力刷新视图兜底方法
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
