#import "ZebraBridge.h"
#import <ExternalAccessory/ExternalAccessory.h>
#import "ZebraPrinterConnection.h"
#import "ZebraPrinter.h"
#import "ZebraPrinterFactory.h"
#import "MfiBtPrinterConnection.h"
#import "GraphicsUtil.h"
#import "NetworkDiscoverer.h"
#import "DiscoveredPrinterNetwork.h"
#import "TcpPrinterConnection.h"
#import "BROTHERSDK.h"
#import "libpng/png.h"
#import <BRLMPrinterKit/BRLMPrinterKit.h>

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
            NSData* data = [NSData dataWithBytes:[zpl UTF8String] length:[zpl length]];
            NSError* writeError;
            
            [connection write:data error:&writeError];
            
            if (writeError == nil) {
                resolve(@{@"message": @"Success!"});
            } else {
                reject(@"", @"", @{@"error": @"Print failed."});
            }
        } else {
            reject(@"", @"", @{@"error": @"Couldn't connect to the accessory."});
        }
    }
}

RCT_EXPORT_METHOD(printImage:(NSString*)serialNumber
                  ipAddress:(NSString*)ipAddress
                  port:(NSInteger)port
                  imageBase64:(NSString*)imageBase64
                  printWithResolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Provided serialNumber: %@", serialNumber);
    NSLog(@"Provided ipAddress: %@", ipAddress);
    NSLog(@"Provided port: %@", [@(port) stringValue]);
    NSLog(@"Provided image: %@", imageBase64);
    
    id<ZebraPrinterConnection, NSObject> connection = nil;
    
    if (ipAddress != nil) {
        connection = [[TcpPrinterConnection alloc] initWithAddress:ipAddress andWithPort:port];
    } else {
        connection = [[MfiBtPrinterConnection alloc] initWithSerialNumber:serialNumber];
    }
    
    bool didOpen = [connection open];
    
    if (didOpen == YES) {
        // Parse image
        NSData* imageData = [[NSData alloc] initWithBase64EncodedString:[imageBase64 stringByReplacingOccurrencesOfString:@"data:image/png;base64," withString:@""] options:NSDataBase64DecodingIgnoreUnknownCharacters];
        
        UIImage* image = [UIImage imageWithData:imageData];
        
        NSError* error;
        id<ZebraPrinter, NSObject> printer = [ZebraPrinterFactory getInstance:connection error:&error];
        
        if (printer != nil) {
            // PrinterLanguage language = [printer getPrinterControlLanguage];
            
            id<GraphicsUtil, NSObject> graphicsUtil = [printer getGraphicsUtil];
            
            NSError* writeError;
            
            [graphicsUtil printImage:[image CGImage] atX:5 atY:15 withWidth:-1 withHeight:-1 andIsInsideFormat:NO error:&writeError];
            
            if (writeError == nil) {
                [connection close];
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

RCT_EXPORT_METHOD(networkScan:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSError* error;
    NSArray* printers = [NetworkDiscoverer localBroadcast:(&error)];

    NSLog(@"Available devices = %@", printers);
    
    NSMutableArray* parsedPrinters = [[NSMutableArray alloc] initWithCapacity:10];
    
    for (id object in printers) {
        if ([object isKindOfClass:[DiscoveredPrinterNetwork class]]) {
            DiscoveredPrinterNetwork* padr = (DiscoveredPrinterNetwork*) object;
            
            NSString* addr = [padr address];
            
            NSLog(@"Address is %@", addr);
            
            
            NSDictionary* parsedPrinter = @{
                @"ipAddress": [padr address],
                @"port": [NSNumber numberWithUnsignedLong:padr.port],
                @"name": [padr dnsName],
            };
            
            [parsedPrinters addObject:parsedPrinter];
        }
    }
        
    NSLog(@"Parsed results %@", parsedPrinters);
    
    resolve(parsedPrinters);
}

RCT_EXPORT_METHOD(printBrotherImage:(NSString*)serialNumber
                  ipAddress:(NSString*)ipAddress
                  imageBase64:(NSString*)imageBase64
                  isTypeB:(bool)isTypeB
                  printWithResolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Provided serialNumber: %@", serialNumber);
    NSLog(@"Provided ipAddress: %@", ipAddress);
    NSLog(@"Provided isTypeB: %@", isTypeB);
    NSLog(@"Provided image: %@", imageBase64);
    
    UIImage* image = [self getImageFromBase64:imageBase64];
    
    if (isTypeB == TRUE) {
        [self printBrotherTypeB:ipAddress image:image];
    } else {
        [self printBrotherSdk4:ipAddress serialNumber:serialNumber image:image];
    }

    resolve(@{@"message": @"Success!"});
}

- (bool) printBrotherTypeB:(NSString *)ipAddress image:(UIImage *)image {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *filePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Receipt.png"];
    
    [self writePngAs1bpp:image toPNG:filePath];
                               
    BROTHERSDK *_lib = [BROTHERSDK new];

    [_lib openport:ipAddress];

    [_lib downloadbmp:filePath asName:@"Receipt.png"];

    [_lib setup:@"72" height:@"40" speed:@"4" density:@"15" sensor:@"0" vertical:@"0" offset:@"0"];
    [_lib clearbuffer];
    [_lib nobackfeed];

    [_lib sendCommand:@"PUTBMP 0,0,\"Receipt.png\"\r\n"];

    [_lib printlabel:@"1" copies:@"1"];

    NSLog([NSString stringWithFormat:@"%@",[_lib printerstatus]]);

    [_lib formfeed];
    [_lib closeport];

    return true;
}

- (bool) printBrotherSdk4:(NSString *)serialNumber ipAddress:(NSString *)ipAddress image:(UIImage *)image {
    BRLMChannel channel = nil;
    
    if (ipAddress != nil) {
        channel = [[BRLMChannel alloc] initWithWifiIPAddress:ipAddress];
    } else {
        channel = [[BRLMChannel alloc] initWithBluetoothSerialNumber:serialNumber];
    }
    
    BRLMPrinterDriverGenerateResult* driverGenerateResult = [BRLMPrinterDriverGenerator openChannel:channel];
    
    if (driverGenerateResult.error.code != BRLMOpenChannelErrorCodeNoError ||
        driverGenerateResult.driver == nil) {
        NSLog(@"%@", @(driverGenerateResult.error.code));
        return false;
    }
    
    BRLMPRinterDriver* printerDriver = driverGenerateResult.driver;
    
    BRLMTDPrintSettings* tdSettings = [[BRLMTDPrintSettings alloc] initDefaultPrintSettingsWithPrinterModel:BRLMPrinterModelTD_YOURS];
    
    BRLMCustomPaperSizeMargins margin = BRLMCustomPaperSizeMarginsMake(0.0, 0.0, 0.0, 0.0);
    BRLMCustomPapertSize* customPaperSize = [[BRLMCustomPaperSize alloc] initRollWithTapeWith:2.0
                                                                                      margins:margin
                                                                                 unitOfLength:BRLMCustomPaperSizeLengthUnitInch];
    
    if (customPaperSize != nil) {
        tdSettings.customPaperSize = customPaperSize;
    }
    
    BRLMPRintError* printError = [printerDriver printImageWithImage:image settings:tdSettings];
    
    if (printError.code != BRLMPrintErrorCodeNoError) {
        NSLog(@"Error - Print Image: %@", @(printError.code));
        
        [channel closeChannel];
        return false;
    }
    
    NSLog(@"Success - Print Image: %@", @(printError.code));
    [channel closeChannel];
    
    return true;
}

- (UIImage *)getImageFromBase64:(NSString *)imageBase64) {
    NSData* imageData = [[NSData alloc] initWithBase64EncodedString:[imageBase64 stringByReplacingOccurrencesOfString:@"data:image/png;base64," withString:@""] options:NSDataBase64DecodingIgnoreUnknownCharacters];

    UIImage* image = [UIImage imageWithData:imageData];
    
    UIImage* binaryImage = [self convertImageToBlackAndWhite:image];
    
    return binaryImage;
}

- (UIImage *)convertImageToBlackAndWhite:(UIImage *)image {
    UIGraphicsBeginImageContextWithOptions(image.size, YES, 1.0);
    
    CGRect imageRect = CGRectMake(0, 0, image.size.width, image.size.height);
    
    // Draw the image with the luminosity blend mode.
    [image drawInRect:imageRect blendMode:kCGBlendModeLuminosity alpha:1.0];
    
    // Get the resulting image.
    UIImage *filteredImage = UIGraphicsGetImageFromCurrentImageContext();
    
    size_t bpp = CGImageGetBitsPerPixel(filteredImage.CGImage);
    
    NSLog([NSString stringWithFormat:@"%zu@", bpp]);
    
    UIGraphicsEndImageContext();

    return filteredImage;
}

- (void) writePngAs1bpp:(UIImage *)uiImage toPNG:(NSString *)file {
    FILE *fp = fopen([file UTF8String], "wb");
    // if (!fp) return [self reportError:[NSString stringWithFormat:@"Unable to open file %@", file]];

    CGImageRef image = [uiImage CGImage];

    CGDataProviderRef provider = CGImageGetDataProvider(image);
    CFDataRef pixelData = CGDataProviderCopyData(provider);
    unsigned char *buffer = (unsigned char *)CFDataGetBytePtr(pixelData);

    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(image);
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(image);
    size_t compBits = CGImageGetBitsPerComponent(image);
    size_t pixelBits = CGImageGetBitsPerPixel(image);
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    NSLog(@"bitmapInfo=%d, alphaInfo=%d, pixelBits=%lu, compBits=%lu, width=%lu, height=%lu", bitmapInfo, alphaInfo, pixelBits, compBits, width, height);

    png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    // if (!png_ptr) [self reportError:@"Unable to create write struct."];

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr) {
        png_destroy_write_struct(&png_ptr, (png_infopp)NULL);
        // return [self reportError:@"Unable to create info struct."];
    }

    if (setjmp(png_jmpbuf(png_ptr))) {
        png_destroy_write_struct(&png_ptr, &info_ptr);
        fclose(fp);
        // return [self reportError:@"Got error callback."];
    }

    png_init_io(png_ptr, fp);
    png_set_IHDR(png_ptr, info_ptr, (png_uint_32)width, (png_uint_32)height, 1, PNG_COLOR_TYPE_GRAY, PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png_ptr, info_ptr);

    png_set_packing(png_ptr);

    png_bytep line = (png_bytep)png_malloc(png_ptr, width);
    unsigned long pos;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            pos = y * width * 4 + x * 4; // multiplying by four because each pixel is represented by four bytes
            line[x] = buffer[ pos ]; // just use the first byte (red) since r=g=b in grayscale
        }
        png_write_row(png_ptr, line);
    }

    png_write_end(png_ptr, info_ptr);

    png_destroy_write_struct(&png_ptr, &info_ptr);
    if (pixelData) CFRelease(pixelData);

    fclose(fp);
}

@end
