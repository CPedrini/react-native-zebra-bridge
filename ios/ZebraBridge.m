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
#import "BRLMPrinterKit.h"
#import "BRLMChannel.h"
#import "BRLMOpenChannelError.h"
#import "BRLMPrinterDriverGenerator.h"
#import "BRLMPrinterDriver.h"
#import "BRLMTDPrintSettings.h"
#import "BRLMCustomPaperSize.h"
#import "BRLMPrinterDefine.h"
#import "BRLMPrintError.h"
#import "ImageMagick.h"
#import "MagickWand.h"

typedef struct PrintResult {
    NSString* message;
    bool success;
};

@implementation ZebraBridge

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(getAccessories:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
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
    
    resolve(parsedAccessories);
}

RCT_EXPORT_METHOD(networkScan:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
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

RCT_EXPORT_METHOD(printImage:(NSDictionary *)parameters
                  printWithResolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Provided parameters: %@", parameters);
    
    NSLog(@"Provided printerSerialNumber: %@", parameters[@"printerSerialNumber"]);
    NSLog(@"Provided printerIpAddress: %@", parameters[@"printerIpAddress"]);
    NSLog(@"Provided printerPort: %@", parameters[@"printerPort"]);
    NSLog(@"Provided printerModel: %@", parameters[@"printerModel"]);
    
    struct PrintResult result;
    UIImage* image;
    
    @try {
        image = [self getImageFromBase64:parameters[@"image"]];
    }
    @catch (NSException* e) {
        reject(@"Error", @"Unable to parse the image. Please try again. If the error persist contact CGME Support.", nil);
        return;
    }
    
    @try {
        NSNumberFormatter *formatter= [[NSNumberFormatter alloc] init];
        [formatter setNumberStyle:NSNumberFormatterDecimalStyle];

        if (parameters[@"printerModel"] == [NSNull null] || [parameters[@"printerModel"] isEqualToString:@"Zebra"]) {
            NSNumber* port = nil;
            
            if (parameters[@"printerPort"] != [NSNull null]) {
                if ([parameters[@"printerPort"] isKindOfClass:[NSNumber class]]) {
                    port = parameters[@"printerPort"];
                } else if ([parameters[@"printerPort"] isKindOfClass:[NSString class]]) {
                    port = [formatter numberFromString:parameters[@"printerPort"]];
                }
            }
            
            result = [self printZebraImage:parameters[@"printerSerialNumber"]
                                 ipAddress:parameters[@"printerIpAddress"]
                                      port:port
                                     image:image];
        } else if ([parameters[@"printerModel"] isEqualToString:@"BrotherSdk4"]) {
            result = [self printBrotherSdk4:parameters[@"printerSerialNumber"]
                                  ipAddress:parameters[@"printerIpAddress"]
                                      image:image];
        } else if ([parameters[@"printerModel"] isEqualToString:@"BrotherSdkTypeB"]) {
            result = [self printBrotherTypeB:parameters[@"printerIpAddress"]
                                       image:image];
        } else {
            reject(@"Error", @"Unsoported model provided. Review your configuration.", nil);
            return;
        }
        
        if (!result.success) {
            reject(@"error", result.message, nil);
            return;
        }
        
        resolve(result.message);
    }
    @catch (NSException* e) {
        reject(@"Error", @"Unknown error. Please try again. If the error persist contact CGME Support.", nil);
        return;
    }
}

- (struct PrintResult) printZebraImage:(NSString*)serialNumber
                       ipAddress:(NSString*)ipAddress
                            port:(NSNumber*)port
                           image:(UIImage*)image
{
    struct PrintResult result;

    id<ZebraPrinterConnection, NSObject> connection = nil;
    
    if (ipAddress != [NSNull null]) {
        connection = [[TcpPrinterConnection alloc] initWithAddress:ipAddress andWithPort:[port integerValue]];
    } else {
        connection = [[MfiBtPrinterConnection alloc] initWithSerialNumber:serialNumber];
    }
    
    bool didOpen = [connection open];
    
    if (didOpen == YES) {
        NSError* error;
        id<ZebraPrinter, NSObject> printer = [ZebraPrinterFactory getInstance:connection error:&error];
        
        if (printer != nil) {
            id<GraphicsUtil, NSObject> graphicsUtil = [printer getGraphicsUtil];
            
            NSError* writeError;
            
            [graphicsUtil printImage:[image CGImage] atX:5 atY:15 withWidth:-1 withHeight:-1 andIsInsideFormat:NO error:&writeError];
            
            if (writeError == nil) {
                result.message = @"Success";
                result.success = true;
            } else {
                result.message = @"Print failed";
                result.success = false;
            }
        } else {
            result.message = @"Couldn't detect language";
            result.success = false;
        }
    } else {
        result.message = @"Couldn't connect to the accessory";
        result.success = false;
    }
    
    [connection close];

    return result;
}

- (struct PrintResult) printBrotherTypeB:(NSString *)ipAddress
                             image:(UIImage *)image
{
    struct PrintResult result;
    
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* originalFilePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"Receipt.png"];
    NSString* parsedFilePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"ReceiptParsed.png"];
    
    [UIImagePNGRepresentation(image) writeToFile:originalFilePath atomically:YES];
    
    UIImage* parsedImage = [self magickConvert:originalFilePath to:parsedFilePath];

    BROTHERSDK *_lib = [BROTHERSDK new];

    NSInteger connectResult = [_lib openport:ipAddress];

    NSInteger setupResult = [_lib setup:@"101" height:@"152" speed:@"14.0" density:@"4" sensor:@"0" vertical:@"-140" offset:@"0"];
    [_lib clearbuffer];
    // [_lib nobackfeed];

//    NSInteger sendImageResult = [_lib sendImagebyFile:parsedImage x:0 y:0 width:8080 height:12160];
    NSInteger sendImageResult = [_lib sendImagebyPath:parsedFilePath x:0 y:0 width:800 height:1300];
    
    NSInteger printResult = [_lib printlabel:@"1" copies:@"1"];

    NSLog([NSString stringWithFormat:@"%@",[_lib printerstatus]]);

    // [_lib formfeed];
    [_lib closeport];
    
    result.success = true;

    return result;
}

- (struct PrintResult) printBrotherSdk4:(NSString *)serialNumber
                              ipAddress:(NSString *)ipAddress
                                  image:(UIImage *)image
{
    struct PrintResult result;

    BRLMChannel* channel = nil;
    
    if (ipAddress != [NSNull null]) {
        channel = [[BRLMChannel alloc] initWithWifiIPAddress:ipAddress];
    } else {
        channel = [[BRLMChannel alloc] initWithBluetoothSerialNumber:serialNumber];
    }
    
    BRLMPrinterDriverGenerateResult* driverGenerateResult = [BRLMPrinterDriverGenerator openChannel:channel];
    
    if (driverGenerateResult.error.code != BRLMOpenChannelErrorCodeNoError || driverGenerateResult.driver == nil) {
        NSLog(@"Connect to Printer - Error Code: %@", @(driverGenerateResult.error.code));

        result.success = false;
        result.message = @"Failed to connect to the printer";
        
        return result;
    }
    
    self.driver = driverGenerateResult.driver;
    
    BRLMTDPrintSettings* tdSettings = [[BRLMTDPrintSettings alloc] initDefaultPrintSettingsWithPrinterModel:BRLMPrinterModelTD_4550DNWB];

    BRLMCustomPaperSizeMargins margin = BRLMCustomPaperSizeMarginsMake(0.0, 0.0, 0.0, 0.0);
    self.paperSize = [[BRLMCustomPaperSize alloc] initRollWithTapeWidth:4.0
                                                                margins:margin
                                                           unitOfLength:BRLMCustomPaperSizeLengthUnitInch];
    
    if (self.paperSize != nil) {
        tdSettings.customPaperSize = self.paperSize;
    }

    tdSettings.halftone = BRLMPrintSettingsHalftoneErrorDiffusion;
    
    BRLMPrintError* printError = [self.driver printImageWithImage:image.CGImage settings:tdSettings];
    
    if (printError.code != BRLMPrintErrorCodeNoError) {
        NSLog(@"Send Image - Error Code: %@", @(printError.code));
        
        [self.driver closeChannel];

        result.success = false;
        result.message = @"Failed to send the image to the printer";
        
        return result;
    }
    
    [self.driver closeChannel];

    result.success = true;
    result.message = @"Success";
    
    return result;
}

- (UIImage *)getImageFromBase64:(NSString *)imageBase64 {
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
    
    NSLog([NSString stringWithFormat:@"Image BPP: %zu@", bpp]);
    
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

- (UIImage*)magickConvert:(NSString*)inputImagePath to:(NSString*)outputImagePath {
    char *inputPath = strdup([inputImagePath UTF8String]);
    char *outputPath = strdup([outputImagePath UTF8String]);
    
    // convert image -colorspace gray +dither -colors 2 -type bilevel result
    
    char *argv[] = {
        "convert",
        inputPath,
        // "-colors", "2",
        "-colorspace", "Gray",
        // "-normalize",
        //"-monochrome",
        "-dither", "FloydSteinberg",
        "-type", "Bilevel",
        "-depth", "1",
        "-compress", "none",
        outputPath,
        NULL
    };
    
    MagickCoreGenesis(*argv, MagickFalse);
    MagickWand *magick_wand = NewMagickWand();
    NSData * dataObject = UIImagePNGRepresentation([UIImage imageWithContentsOfFile:inputImagePath]);
    MagickBooleanType status;
    status = MagickReadImageBlob(magick_wand, [dataObject bytes], [dataObject length]);
    
    if (status == MagickFalse) {
        NSLog(@"Error %@", magick_wand);
    }
    
    ImageInfo *imageInfo = AcquireImageInfo();
    ExceptionInfo *exceptionInfo = AcquireExceptionInfo();
    
    int elements = 0;
    while (argv[elements] != NULL)
    {
        elements++;
    }
    
    // ConvertImageCommand(ImageInfo *, int, char **, char **, MagickExceptionInfo *);
    status = ConvertImageCommand(imageInfo, elements, argv, NULL, exceptionInfo);
    
    if (exceptionInfo->severity != UndefinedException)
    {
        status=MagickTrue;
        CatchException(exceptionInfo);
    }
    
    if (status == MagickFalse) {
        fprintf(stderr, "Error in call");
        // ThrowWandException(magick_wand); // Always throws an exception here...
    }
    
    UIImage *convertedImage = [UIImage imageWithContentsOfFile:outputImagePath];
    
    return convertedImage;
}

@end
