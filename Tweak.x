#import <UIKit/UIKit.h>

// 声明转转的私有类和方法，消除编译警告
@interface ZZListingAprilViewController : UIViewController
@property (retain, nonatomic) NSArray *dataArray;
- (void)loadData;
- (void)real_reloadData:(id)arg;

// 声明我们要动态注入的方法
- (void)custom_twoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)custom_filterListWithVersion:(NSString *)version;
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
        
        UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"开始筛选" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSString *versionText = alert.textFields.firstObject.text;
            if (versionText.length > 0) {
                [self custom_filterListWithVersion:versionText];
            }
        }];
        
        UIAlertAction *resetAction = [UIAlertAction actionWithTitle:@"重置列表" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            // 调用它原生的 loadData 方法重新请求网络，恢复初始未过滤的数据
            if ([self respondsToSelector:@selector(loadData)]) {
                [self performSelector:@selector(loadData)];
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
- (void)custom_filterListWithVersion:(NSString *)version {
    NSArray *currentData = self.dataArray;
    if (!currentData || currentData.count == 0) {
        return;
    }
    
    NSMutableArray *filteredArray = [NSMutableArray array];
    
    // 遍历当前列表数据
    for (id item in currentData) {
        BOOL isMatch = NO;
        
        @try {
            // 1. 尝试匹配商品标题
            NSString *title = [item valueForKey:@"title"];
            if ([title isKindOfClass:[NSString class]] && [title containsString:version]) {
                isMatch = YES;
            }
            
            // 2. 尝试匹配 ZZSearchResultListModel 中的 desc (描述信息)
            if (!isMatch) {
                NSString *desc = [item valueForKey:@"desc"];
                if ([desc isKindOfClass:[NSString class]] && [desc containsString:version]) {
                    isMatch = YES;
                }
            }
            
            // 3. 尝试匹配 Swift 模型 ZZCommonFeedGoodsModel 里的扩展参数 extendJson
            if (!isMatch) {
                NSString *extendJson = [item valueForKey:@"extendJson"];
                if ([extendJson isKindOfClass:[NSString class]] && [extendJson containsString:version]) {
                    isMatch = YES;
                }
            }
            
            // 4. 终极兜底方案：转转的参数经常存在嵌套模型 (如 labelPosition) 里
            // 直接获取该 Item 对象的整体描述（包含嵌套参数），只要该模型携带了版本号数据就能命中
            if (!isMatch) {
                NSString *itemDesc = [item description];
                if ([itemDesc containsString:version]) {
                    isMatch = YES;
                }
            }
        } @catch (NSException *exception) {
            // 忽略 valueForKey 在对象上找不到对应属性抛出的异常
        }
        
        // 匹配成功则放入筛选数组
        if (isMatch) {
            [filteredArray addObject:item];
        }
    }
    
    // 筛选结果判断
    if (filteredArray.count > 0) {
        // 覆盖原生数据源
        self.dataArray = [filteredArray copy];
        
        // 尝试调用转转内部自带的刷新方法
        if ([self respondsToSelector:@selector(real_reloadData:)]) {
            [self performSelector:@selector(real_reloadData:) withObject:nil];
        } else {
            // 如果私有方法失效，暴力遍历视图寻找 CollectionView 刷新
            [self custom_reloadCollectionView];
        }
        
    } else {
        // 没搜到当前页面有该版本时进行弹窗提示
        UIAlertController *emptyAlert = [UIAlertController alertControllerWithTitle:@"筛选失败" 
                                                                            message:@"当前这页未找到该 iOS 版本的设备。\n您可以向下滑动加载更多数据后，再次双指长按进行筛选。" 
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [emptyAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:emptyAlert animated:YES completion:nil];
    }
}

%new
- (void)custom_reloadCollectionView {
    // 广度优先搜索 (BFS) 查找页面内的 UICollectionView 并强制重载数据
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
