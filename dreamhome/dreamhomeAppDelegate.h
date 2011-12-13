//
//  dreamhomeAppDelegate.h
//

#import <UIKit/UIKit.h>

@class dreamhomeViewController;

@interface dreamhomeAppDelegate : NSObject <UIApplicationDelegate>

@property (nonatomic, retain) IBOutlet UIWindow *window;

@property (nonatomic, retain) IBOutlet dreamhomeViewController *viewController;

@end
