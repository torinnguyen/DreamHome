//
//  dreamhomeViewController.m
//

#import "dreamhomeViewController.h"

#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <ifaddrs.h>

@interface dreamhomeViewController ()
    @property (nonatomic, retain) NSTimer* timer;
    - (void)onTimer:(NSTimer*)timer;
@end


@implementation dreamhomeViewController

#define BEACON_PORT         9131
#define STATUS_PORT         4998
#define SERIAL_DATA_PORT    4999
#define BEACON_TAG          0
#define STATUS_TAG          1
#define SERIAL_DATA_TAG     2
#define MULTICASTGROUP      @"239.255.250.250"

@synthesize ipAddr;
@synthesize timer;

#pragma mark - Custom Initialization

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
    }
    return self;
}

#pragma mark - Standard Initialization

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //Clear background color
    self.view.backgroundColor = [UIColor clearColor];
    
    //Hide the default navbar
    self.navigationController.navigationBarHidden = YES;      
}

- (void)viewDidUnload
{
    self.ipAddr = nil;
    
    if (self.timer != nil)
        [self.timer invalidate];
    self.timer = nil;
    
    //Important!!
    asyncUdpSocket.delegate = nil;
    asyncTcpSocketStatus.delegate = nil;
    asyncTcpSocketSerial.delegate = nil;
    
    [asyncUdpSocket release];
    [asyncTcpSocketStatus release];
    [asyncTcpSocketSerial release];
    
    asyncUdpSocket = nil;
    asyncTcpSocketStatus = nil;
    asyncTcpSocketSerial = nil;
    
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    //For debugging
    NSLog(@"my ip address: %@", [self getIPAddress]);
    
    [self reset];
}

- (void)viewWillDisappear:(BOOL)animated
{  
	[super viewWillDisappear:animated];    
}



#pragma mark - UI Helpers





#pragma mark - UI Events

- (IBAction)onBtnTop:(id)sender         {   [self sendSerialCommand:@"20"];    }
- (IBAction)onBtnBottom:(id)sender      {   [self sendSerialCommand:@"21"];    }

- (void)onTimer:(NSTimer*)whichTimer
{
    //Everything is normal, clean up the timer
    if ([asyncTcpSocketSerial isConnected])
    {
        [whichTimer invalidate];
        if (whichTimer == self.timer)
            self.timer = nil;
        return;
    }
    
    //Did not receive any beacon, hence not connected
    //Show current WiFi IP Address for diagnostic
    [self setStatusText:[NSString stringWithFormat:@"Error %@", [self getIPAddress]] withColor:[UIColor redColor]];
    
    NSLog(@"timer timeout! my ip address: %@", [self getIPAddress]);
}


#pragma mark - Helper functions

- (void)reset
{
    NSLog(@"reseting...");
        
    //Device list
    if (deviceList == nil)
        deviceList = [[NSMutableDictionary alloc] initWithCapacity:10];
    [deviceList removeAllObjects];
    
    //UDP socket for listening to beacon
    if (asyncUdpSocket == nil)
        asyncUdpSocket = [[AsyncUdpSocket alloc] initWithDelegate:self userData:BEACON_TAG];
    [asyncUdpSocket bindToPort:BEACON_PORT error:nil];
    [asyncUdpSocket joinMulticastGroup:MULTICASTGROUP error:nil];
    
    //TCP socket for status & control
    if (asyncTcpSocketStatus == nil)
        asyncTcpSocketStatus = [[AsyncSocket alloc] initWithDelegate:self];
    
    //TCP socket for serial data
    if (asyncTcpSocketSerial == nil)
        asyncTcpSocketSerial = [[AsyncSocket alloc] initWithDelegate:self];
    
    //For the app to work when coming back from background
    asyncUdpSocket.delegate = self;
    asyncTcpSocketStatus.delegate = self;
    asyncTcpSocketSerial.delegate = self;
    
    //Start listening
    [asyncUdpSocket receiveWithTimeout:-1 tag:1];
    
    //Clear UI
    [self setStatusText:@"scanning..." withColor:[UIColor whiteColor]];
    
    //Setup long timer
    self.timer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
}

- (void)setStatusText:(NSString*)text withColor:(UIColor*)color
{
    ipAddr.text = text;
    ipAddr.textColor = color;
}

- (NSDictionary *)parseBeaconString:(NSString*)string
{
    //Preamble
    NSRange range = [string rangeOfString:@"AMXB" options: NSCaseInsensitiveSearch];
    if (range.location != 0 || range.length != 4)
        return nil;
    string = [string substringFromIndex:range.length];
    
    //Dict for returning
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity:5];
    
    //1st level
    NSArray *firstLevel = [string componentsSeparatedByString:@"<-"];
    if ([firstLevel count] < 2) {
        [dict release];
        return nil;
    }
    
    for (int i=0; i<[firstLevel count]; i++)
    {
        if ([firstLevel objectAtIndex:i] == nil)
            continue;
        if (![[firstLevel objectAtIndex:i] isKindOfClass:[NSString class]])
            continue;
        NSArray *secondLevel = [(NSString*)[firstLevel objectAtIndex:i] componentsSeparatedByString:@"="];
        
        if (secondLevel == nil || [secondLevel count] < 2)
            continue;
        if (![[secondLevel objectAtIndex:0] isKindOfClass:[NSString class]])
            continue;
        if (![[secondLevel objectAtIndex:1] isKindOfClass:[NSString class]])
            continue;
        
        NSString * key = (NSString*)[secondLevel objectAtIndex:0];
        NSString * value = (NSString*)[secondLevel objectAtIndex:1];
        value = [value substringToIndex:([value length] - 1)];        //remove trailing '>' character
        
        [dict setObject:value forKey:key];
    }
    
    if ([dict count] <= 0) {
        [dict release];
        return nil;
    }
    
    //Post processing
    NSString *configUrl = [dict objectForKey:@"Config-URL"];
    if (configUrl == nil) {
        [dict release];
        return nil;
    }
    
    //Add convenient IP address field
    NSRange wholeString = NSMakeRange(0, [configUrl length]);
    NSMutableString *ip = [NSMutableString stringWithString:configUrl];
    [ip replaceOccurrencesOfString:@"http://" withString:@"" options:0 range:wholeString];
    [dict setObject:[NSString stringWithString:ip] forKey:@"IP"];
    
    return [dict autorelease];
}


- (NSDictionary *)parseGetDevice:(NSString*)string
{
    //Preamble
    NSRange range = [string rangeOfString:@"device," options: NSCaseInsensitiveSearch];
    if (range.location != 0 || range.length != 7)
        return nil;
    
    //Dict for returning
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity:3];
    
    //1st level
    NSArray *firstLevel = [string componentsSeparatedByString:@"\r"];
    if ([firstLevel count] < 2) {
        [dict release];
        return nil;
    }
    
    NSLog(@"%@", string);
    
    for (int i=0; i<[firstLevel count]; i++)
    {
        if ([firstLevel objectAtIndex:i] == nil)
            continue;
        if (![[firstLevel objectAtIndex:i] isKindOfClass:[NSString class]])
            continue;
        
        NSArray *secondLevel = [(NSString*)[firstLevel objectAtIndex:i] componentsSeparatedByString:@"="];
        
        if (secondLevel == nil || [secondLevel count] < 3)
            continue;
        if (![[secondLevel objectAtIndex:0] isKindOfClass:[NSString class]])
            continue;
        if (![[secondLevel objectAtIndex:1] isKindOfClass:[NSString class]])
            continue;
        if (![[secondLevel objectAtIndex:2] isKindOfClass:[NSString class]])
            continue;
        
        NSString * preamble = (NSString*)[secondLevel objectAtIndex:0];
        if (![preamble isEqualToString:@"device"])
            continue;
        
        NSString * addr = (NSString*)[secondLevel objectAtIndex:1];
        NSString * type = (NSString*)[secondLevel objectAtIndex:2];
        
        [dict setObject:type forKey:addr];
    }
    
    if ([dict count] <= 0) {
        [dict release];
        return nil;
    }
    
    return [dict autorelease];
}



#pragma mark - Sending command

- (long)getCommandTag:(NSString*)commandName
{
    if ([commandName isEqualToString:@"getdevices"])         return 0;
    if ([self string:commandName contains:@"set_SERIAL"])   return 1;
    if ([self string:commandName contains:@"get_SERIAL"])   return 2;
    return -1;
}

- (void)sendCommand:(NSString*)string
{
    if (asyncTcpSocketStatus == nil || ![asyncTcpSocketStatus isConnected])
        return;
    NSLog(@"Sending command: %@", string);
    NSString *commandString = [NSString stringWithFormat:@"%@\r\n", string];
    [asyncTcpSocketStatus writeData:[commandString dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:[self getCommandTag:string]];
}

- (void)sendSerialCommand:(NSString*)string
{
    if (asyncTcpSocketSerial == nil || ![asyncTcpSocketSerial isConnected])
        return;
    NSLog(@"Sending serial command: %@", string);
    NSString *commandString = [NSString stringWithFormat:@"%@\r\n", string];
    [asyncTcpSocketSerial writeData:[commandString dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:0];
}



#pragma mark - Utilities

- (BOOL)string:(NSString*)string contains:(NSString*)anotherString
{
    NSRange range = [string rangeOfString:anotherString options: NSCaseInsensitiveSearch];
    if (range.location != 0 || range.length != [anotherString length])
        return NO;
    return YES;
}

- (NSString *)getIPAddress 
{
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0)  
    {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL)  
        {
            if(temp_addr->ifa_addr->sa_family == AF_INET)
            {
                // Check if interface is en0 which is the wifi connection on the iPhone  
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"])  
                {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces); 
    return address; 
}


#pragma mark - AsyncUdpSocket delegate

//Received data while listening
- (BOOL)onUdpSocket:(AsyncUdpSocket *)sock didReceiveData:(NSData *)data withTag:(long)tag fromHost:(NSString *)host port:(UInt16)port
{
    //Convert the NSData to an NSString
    NSString *theLine=[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];    
    
    NSDictionary *beaconDict = [self parseBeaconString:theLine];
    if (beaconDict != nil)
    {
        NSString *ip = [beaconDict objectForKey:@"IP"];       
        if ([deviceList objectForKey:ip] == nil)
            NSLog(@"%@", [beaconDict description]);
        [deviceList setObject:beaconDict forKey:ip];
        
        //Connect to the first device found
        if (![asyncTcpSocketStatus isConnected])
        {
            [self setStatusText:[NSString stringWithFormat:@"Controlling %@", ip] withColor:[UIColor whiteColor]];
            
            NSError *err = nil;
            if (![asyncTcpSocketStatus connectToHost:ip onPort:STATUS_PORT error:&err])
                NSLog(@"asyncTcpSocketStatus connect error: %@", err);
        }
        if (![asyncTcpSocketSerial isConnected])
        {
            NSError *err = nil;
            if (![asyncTcpSocketSerial connectToHost:ip onPort:SERIAL_DATA_PORT error:&err])
                NSLog(@"asyncTcpSocketSerial connect error: %@", err);
        }
    }
    
    //Listen for the next UDP packet to arrive...which will call this method again in turn
    [sock receiveWithTimeout:-1 tag:1];
    return YES;
}

- (void)onUdpSocket:(AsyncUdpSocket *)sock didNotReceiveDataWithTag:(long)tag dueToError:(NSError *)error
{
    
}

- (void)onUdpSocket:(AsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
    
}



#pragma mark - AsyncSocket delegate

- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
    NSLog(@"didConnectToHost %@:%d", host, port);
    NSLog(@"my ip address: %@", [self getIPAddress]);
    
    if (sock == asyncTcpSocketStatus)
    {
        NSString *commandName = @"getdevices\r";
        [sock writeData:[commandName dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:0];
        
        //[self sendCommand:@"getdevices"];
        //[self sendCommand:@"set_SERIAL,1:1,9600,FLOW_NONE,PARITY_NO"];
        //[self sendCommand:@"get_SERIAL,1:1"];
    }
    else if (sock == asyncTcpSocketSerial)
    {
        [self sendSerialCommand:@"/01"];
    }
}

- (void)onSocket:(AsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    NSLog(@"didWriteDataWithTag");
    [sock readDataToLength:256 withTimeout:-1 tag:tag];
}

- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    NSLog(@"didReadData");
    
    //Convert the NSData to an NSString
    NSString *theLine=[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if (theLine == nil || [theLine length] < 2)
        return;
    
    if (sock == asyncTcpSocketStatus)
    {
        [self onReceiveSocketStatus:sock didReadData:theLine withTag:tag];
    }
    else if (sock == asyncTcpSocketSerial)
    {
        [self onReceiveSocketSerial:sock didReadData:theLine withTag:tag];
    }
}

- (void)onReceiveSocketStatus:(AsyncSocket *)sock didReadData:(NSString *)string withTag:(long)tag
{
    if (tag == [self getCommandTag:@"getdevices"])
    {
        NSDictionary *getDeviceDict = [self parseGetDevice:string];
        if (getDeviceDict == nil)
            return;
    }
    else if (tag == [self getCommandTag:@"get_SERIAL"])
    {
        NSLog(@"%@", string);
    }
}

- (void)onReceiveSocketSerial:(AsyncSocket *)sock didReadData:(NSString *)string withTag:(long)tag
{
    NSLog(@"Serial data: %@", string);
}

@end
