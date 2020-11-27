#import "ZebraBridge.h"
#import <ExternalAccessory/ExternalAccessory.h>
#import "ZebraPrinterConnection.h"
#import "ZebraPrinter.h"
#import "ZebraPrinterFactory.h"
#import "MfiBtPrinterConnection.h"
#import "GraphicsUtil.h"

@implementation ZebraBridge

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(sampleMethod:(NSString *)stringArgument numberParameter:(nonnull NSNumber *)numberArgument callback:(RCTResponseSenderBlock)callback)
{
    // TODO: Implement some actually useful functionality
    callback(@[[NSString stringWithFormat: @"numberArgument: %@ stringArgument: %@", numberArgument, stringArgument]]);
}

RCT_EXPORT_METHOD(getAccessories:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    EAAccessoryManager *manager = [EAAccessoryManager sharedAccessoryManager];
    
    NSArray* connectedAccessories = [manager connectedAccessories];

    NSLog(@"Connected Accessories = %@", connectedAccessories);
    
    NSMutableArray* parsedAccessories = [[NSMutableArray alloc] initWithCapacity:10];
    
    for (EAAccessory* managerAccessory in connectedAccessories) {
        NSDictionary* accessory = @{
            @"connectionID": [NSNumber numberWithUnsignedLong:managerAccessory.connectionID],
            @"name": managerAccessory.name,
            @"manufacturer": managerAccessory.manufacturer,
            @"modelNumber": managerAccessory.modelNumber,
            @"serialNumber": managerAccessory.serialNumber
        };
        
        [parsedAccessories addObject:accessory];
    }
    
    // NSError* error = nil;
    
    // NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parsedAccessories options:NSJSONWritingPrettyPrinted error:&error];
    
    // NSString * jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    resolve(parsedAccessories);
}

RCT_EXPORT_METHOD(printZpl:(NSString*)serialNumber
                 zpl:(NSString*)zpl
                 printWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Provided serialNumber: %@", serialNumber);
    NSLog(@"Provided zpl: %@", zpl);
    
    EAAccessoryManager *manager = [EAAccessoryManager sharedAccessoryManager];
    
    EAAccessory* connectedAccessories = [manager connectedAccessories];

    // Find accessory, we need to be sure that it is still there.

    EAAccessory* accessory = nil;
    
    for (EAAccessory* managerAccessory in connectedAccessories) {
        if ([serialNumber isEqualToString:managerAccessory.serialNumber]) {
            accessory = managerAccessory;
        }
    }
    
    if (!accessory) {
        reject(@"", @"", @{@"error": @"Accessory not found."});
    } else {
        // Connect to the device.
        
        id<ZebraPrinterConnection, NSObject> connection = [[MfiBtPrinterConnection alloc] initWithSerialNumber:serialNumber];
        
        bool didOpen = [connection open];
        
        if (didOpen == YES) {
            NSError* error;
            id<ZebraPrinter, NSObject> printer = [ZebraPrinterFactory getInstance:connection error:&error];
            
            if (printer != nil) {
                // PrinterLanguage language = [printer getPrinterControlLanguage];

                NSData* data = [NSData dataWithBytes:[zpl UTF8String] length:[zpl length]];
                NSError* writeError;
                
                [connection write:data error:&writeError];
                
                if (writeError == nil) {
                    resolve(@{@"message": @"Success!"});
                } else {
                    reject(@"", @"", @{@"error": @"Print failed."});
                }
            } else {
                reject(@"", @"", @{@"error": @"Couldn't detect language."});
            }
        } else {
            reject(@"", @"", @{@"error": @"Couldn't connect to the accessory."});
        }
    }
}

RCT_EXPORT_METHOD(printImage:(NSString*)serialNumber
                  imageBase64:(NSString*)imageBase64
                  printWithResolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Provided serialNumber: %@", serialNumber);
    NSLog(@"Provided image: %@", imageBase64);
    
    // Parse image
    
    NSData* imageData = [[NSData alloc] initWithBase64EncodedString:[imageBase64 stringByReplacingOccurrencesOfString:@"data:image/png;base64," withString:@""] options:NSDataBase64DecodingIgnoreUnknownCharacters];
    
    UIImage* image = [UIImage imageWithData:imageData];
    
    // Get accesories
    
    EAAccessoryManager *manager = [EAAccessoryManager sharedAccessoryManager];
    
    EAAccessory* connectedAccessories = [manager connectedAccessories];

    // Find accessory, we need to be sure that it is still there.

    EAAccessory* accessory = nil;
    
    for (EAAccessory* managerAccessory in connectedAccessories) {
        if ([serialNumber isEqualToString:managerAccessory.serialNumber]) {
            accessory = managerAccessory;
        }
    }
    
    if (!accessory) {
        reject(@"", @"", @{@"error": @"Accessory not found."});
    } else {
        // Connect to the device.
        
        id<ZebraPrinterConnection, NSObject> connection = [[MfiBtPrinterConnection alloc] initWithSerialNumber:serialNumber];
        
        bool didOpen = [connection open];
        
        if (didOpen == YES) {
            NSError* error;
            id<ZebraPrinter, NSObject> printer = [ZebraPrinterFactory getInstance:connection error:&error];
            
            if (printer != nil) {
                // PrinterLanguage language = [printer getPrinterControlLanguage];
                
                id<GraphicsUtil, NSObject> graphicsUtil = [printer getGraphicsUtil];
                
                NSError* writeError;
                
                [graphicsUtil printImage:[image CGImage] atX:5 atY:15 withWidth:-1 withHeight:-1 andIsInsideFormat:NO error:&writeError];
                
                if (writeError == nil) {
                    resolve(@{@"message": @"Success!"});
                } else {
                    reject(@"", @"", @{@"error": @"Print failed."});
                }
            } else {
                reject(@"", @"", @{@"error": @"Couldn't detect language."});
            }
        } else {
            reject(@"", @"", @{@"error": @"Couldn't connect to the accessory."});
        }
    }
}

@end
