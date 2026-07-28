#import <UIKit/UIKit.h>

// 声明我们要用到的转转内部类
@interface ZZInfoDetailRequestModel : NSObject
@property (copy, nonatomic) NSString *infoID;
@end

@interface ZZGoodsDetailProxy : NSObject
// 声明请求方法，这里我们把 block 类型显式声明出来
- (void)requestGoodsDetailDateWithRequestModel:(id)a0 success:(void(^)(id response))a1 failure:(void(^)(id error))a2;
@end

@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
- (void)loadData;
- (void)real_reloadData:(id)arg;

// 我们的自定义方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_fetchDetailAndFilterWithVersion:(NSString *)version;
- (void)custom_reloadCollectionView;
@end


%hook ZZListingAprilViewController

- (void)viewDidLoad {
    %orig;
    
    // 给当前 Controller 的 View 添加双指长按手势
    UILongPressGestureRecognizer *twoFingerLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(custom_twoFingerLongPress:)];
    twoFingerLongPress.numberOfTouchesRequired = 2; // 需要两个手指
    twoFingerLongPress.minimumPressDuration = 1.0;  // 长按时间为 1 秒
    [self.view addGestureRecognizer:twoFingerLongPress];
}

%new
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    // 仅在手势刚识别时触发一次弹窗
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"系统版本筛选" 
                                                                       message:@"请输入你想筛选的系统版本号\n(例如: 15.4、16.1)" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"输入 iOS 版本号";
            // 使用带有数字和标点符号的键盘
            textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        __weak typeof(self) weakSelf = self;
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"开始后台筛选" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
    NSArray *currentData = self.dataArray;
    if (!currentData || currentData.count == 0) {
        return;
    }
    
    // 1. 弹出全局 Loading 提示，防止用户在这期间乱点
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在静默拉取详情..." 
                                                                          message:@"后台正在分析当前页所有商品的详细参数\n请稍候..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    // 2. 初始化并发控制组和线程锁
    dispatch_group_t group = dispatch_group_create();
    NSMutableSet *matchedInfoIds = [NSMutableSet set]; // 用于存放命中版本的商品 infoId
    NSLock *lock = [[NSLock alloc] init];              // 防止多线程写入 Set 崩溃
    
    // 3. 遍历当前列表所有的商品，发起静默网络请求
    for (id item in currentData) {
        NSString *infoId = nil;
        @try {
            infoId = [item valueForKey:@"infoId"];
        } @catch (NSException *e) {}
        
        if (!infoId || infoId.length == 0) {
            continue;
        }
        
        // 标记进入请求组
        dispatch_group_enter(group);
        
        // 构造请求 Model
        ZZInfoDetailRequestModel *reqModel = [[NSClassFromString(@"ZZInfoDetailRequestModel") alloc] init];
        reqModel.infoID = infoId;
        
        // 实例化 Proxy 发起请求
        ZZGoodsDetailProxy *proxy = [[NSClassFromString(@"ZZGoodsDetailProxy") alloc] init];
        [proxy requestGoodsDetailDateWithRequestModel:reqModel success:^(id response) {
            BOOL isMatch = NO;
            @try {
                // response 就是 ZZGoodsDetailModel
                // 我们解析它的 param 数组 (里面是 ZZGoodsDetailParamModel)
                NSArray *params = [response valueForKey:@"param"];
                if (params && [params isKindOfClass:[NSArray class]]) {
                    for (id paramItem in params) {
                        NSString *paramValue = [paramItem valueForKey:@"paramValue"];
                        // 如果参数值包含了用户输入的版本号 (例如 "15.4")
                        if ([paramValue isKindOfClass:[NSString class]] && [paramValue containsString:version]) {
                            isMatch = YES;
                            break;
                        }
                    }
                }
                
                // 终极兜底：如果参数解析不到，但在整个详情数据字符串里包含版本号，也算命中
                if (!isMatch) {
                    NSString *fullDesc = [response description];
                    if ([fullDesc containsString:version]) {
                        isMatch = YES;
                    }
                }
            } @catch (NSException *e) {}
            
            // 如果命中，把 infoId 存入集合
            if (isMatch) {
                [lock lock];
                [matchedInfoIds addObject:infoId];
                [lock unlock];
            }
            
            // 标记请求离开组
            dispatch_group_leave(group);
            
        } failure:^(id error) {
            // 失败也要离开组，避免死锁
            dispatch_group_leave(group);
        }];
    }
    
    __weak typeof(self) weakSelf = self;
    
    // 4. 所有商品详情拉取完毕后触发
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            
            // 重新按原来的商品顺序把命中的商品组装成新的数组 (保证 UI 不错乱)
            NSMutableArray *sortedFilteredArray = [NSMutableArray array];
            for (id item in currentData) {
                NSString *infoId = nil;
                @try { infoId = [item valueForKey:@"infoId"]; } @catch (NSException *e) {}
                
                if (infoId && [matchedInfoIds containsObject:infoId]) {
                    [sortedFilteredArray addObject:item];
                }
            }
            
            // 5. 替换数据并刷新
            if (sortedFilteredArray.count > 0) {
                weakSelf.dataArray = [sortedFilteredArray copy];
                
                if ([weakSelf respondsToSelector:@selector(real_reloadData:)]) {
                    [weakSelf performSelector:@selector(real_reloadData:) withObject:nil];
                } else {
                    [weakSelf custom_reloadCollectionView];
                }
            } else {
                // 如果本页没有匹配的商品
                UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"筛选结果" 
                                                                                    message:@"当前页的商品详情中均未找到该 iOS 版本。\n您可以向下滑动加载更多数据后，再次双指长按进行筛选。" 
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [weakSelf presentViewController:emptyAlert animated:YES completion:nil];
            }
        }];
    });
}

%new
- (void)custom_reloadCollectionView {
    // 广度优先搜索寻找 CollectionView 刷新
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
