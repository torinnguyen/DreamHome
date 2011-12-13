//
//  dreamhomeViewController.h
//

#import <UIKit/UIKit.h>
#import "AsyncUdpSocket.h"
#import "AsyncSocket.h"

@interface dreamhomeViewController : UIViewController <AsyncUdpSocketDelegate, AsyncSocketDelegate>
{
    AsyncUdpSocket *asyncUdpSocket;
    AsyncSocket *asyncTcpSocketStatus;
    AsyncSocket *asyncTcpSocketSerial;
    
    NSMutableDictionary *deviceList;
}
@property (nonatomic, retain) IBOutlet UILabel *ipAddr;

// UI Events
- (IBAction)onBtnTop:(id)sender;
- (IBAction)onBtnBottom:(id)sender;

//Helper functions
- (NSDictionary *)parseBeaconString:(NSString*)string;
- (NSDictionary *)parseGetDevice:(NSString*)string;

//Sending command
- (long)getCommandTag:(NSString*)commandName;
- (void)sendCommand:(NSString*)string;
- (void)sendSerialCommand:(NSString*)string;

//Utilities
- (BOOL)string:(NSString*)string contains:(NSString*)anotherString;

// Data Events
- (void)onReceiveSocketStatus:(AsyncSocket *)sock didReadData:(NSString *)string withTag:(long)tag;
- (void)onReceiveSocketSerial:(AsyncSocket *)sock didReadData:(NSString *)string withTag:(long)tag;

@end
