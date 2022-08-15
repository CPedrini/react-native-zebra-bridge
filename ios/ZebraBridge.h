#import <React/RCTBridgeModule.h>
#import <ExternalAccessory/ExternalAccessory.h>
#import "BRLMPrinterDriver.h"
#import "BRLMCustomPaperSize.h"

@interface ZebraBridge : NSObject <RCTBridgeModule>

@property(nonatomic,retain)NSMutableArray *bluetoothPrinters;
@property(nonatomic, strong) BRLMPrinterDriver* driver;
@property (nonatomic) BRLMCustomPaperSize* paperSize;

@end
