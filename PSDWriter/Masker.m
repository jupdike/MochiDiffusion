//
//  Masker.m
//  Mochi Diffusion
//
//  Created by Jared Updike on 3/4/25.
//

#import <Foundation/Foundation.h>
#include <math.h>

#import "Masker.h"

@implementation Masker

- (id)init {
    self = [super init];
    if (self) {
        _width = 0;
        _height = 0;
        imageRef = NULL;
    }
    return self;
}

#define BYTES_PER_PIXEL 4
- (id)initWithWidth:(size_t)w height:(size_t)h {
    self = [self init];
    if (!self) {
        return self;
    }
    self->_width = w;
    self->_height = h;
    self->_data = (uint8_t*)malloc(BYTES_PER_PIXEL * w * h); // one byte per Channel
    self->imageRef = NULL;
    return self;
}

- (id)initWithColorImageWithTaper:(CGImageRef)cgimage {
    self = [[Masker alloc] initWithTaperedColorImage:cgimage];
    return self;
}

- (id)initWithColorImage:(CGImageRef)cgimage {
    self = [[Masker alloc] initWithImage:cgimage];
    return self;
}

// private
- (id)initWithTaperedColorImage:(CGImageRef)cgimage {
    return [self initWithImage:cgimage shouldTaper:YES];
}

- (id)initWithImage:(CGImageRef)cgimage {
    return [self initWithImage:cgimage shouldTaper:NO];
}

- (CGImageRef)toImage {
    size_t bufferLength = _width * _height * BYTES_PER_PIXEL;
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, _data, bufferLength, NULL);
    size_t bitsPerComponent = 8;
    size_t bitsPerPixel = BYTES_PER_PIXEL * bitsPerComponent;
    size_t bytesPerRow = BYTES_PER_PIXEL * _width;

    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    if(colorSpaceRef == NULL) {
        NSLog(@"Error allocating color space");
        CGDataProviderRelease(provider);
        return nil;
    }

    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast;
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;

    CGImageRef iref = CGImageCreate(_width, _height,
                    bitsPerComponent, bitsPerPixel,
                    bytesPerRow, colorSpaceRef,
                    bitmapInfo,
                    provider,   // data provider
                    NULL,       // decode
                    NO,            // should interpolate
                    renderingIntent);
    return iref;
}

// smoothly transition domain of (0 -> 1) to range of (0 -> 1)
// bad things happen outside of that range
double sigmoid(double x) {
    return (( sin( (2 * x - 1) * M_PI / 2 ) + 1) / 2);
    //return x;
}

// RAT   * SMALLER DIM
// 0.055 * 1280 = 70 pixels
// 0.055 * 1080 = 60 pixels
// 0.055 * 512  = 28 pixels
//#define TAPER_RAT (0.08)
uint8_t taper(uint8_t val, double taperSize, int w, int h, int x, int y) {
    if (x > taperSize && x < w-1 - taperSize &&
        y > taperSize && y < h-1 - taperSize) {
        return val;
    }
    double mul = 1.0;
    if (x <= taperSize) {
        double domain = x / taperSize;
        mul *= sigmoid(domain);
    } else if (x >= w-1 - taperSize) {
        double domain = (w-1 - x) / taperSize;
        mul *= sigmoid(domain);
    }
    if (y <= taperSize) {
        double domain = y / taperSize;
        mul *= sigmoid(domain);
    } else if (y >= h-1 - taperSize) {
        double domain = (h-1 - y) / taperSize;
        mul *= sigmoid(domain);
    }
    const double other = 0.0; // transparent, for alpha channel
    val = val * mul + other * (1.0 - mul); // mix gray into edges
    return (uint8_t)MYCLAMP(val, 0, 255);
}

- (id)initWithImage:(CGImageRef)cgimage shouldTaper:(BOOL)shouldTaper {
    self = [self init];
    if (!self) {
        return self;
    }
    self->_width = CGImageGetWidth(cgimage);
    self->_height = CGImageGetHeight(cgimage);
    //NSLog(@"w x h = %ld x %ld\n", self->_width, self->_height);

    size_t width  = CGImageGetWidth(cgimage);
    size_t height = CGImageGetHeight(cgimage);

    size_t bpr = CGImageGetBytesPerRow(cgimage);
    size_t bpp = CGImageGetBitsPerPixel(cgimage);
    size_t bpc = CGImageGetBitsPerComponent(cgimage);
    size_t bytes_per_pixel = bpp / bpc;

    //CGBitmapInfo info = CGImageGetBitmapInfo(cgimage);

//    NSLog(
//        @"CGImageGetHeight: %d\n"
//        @"CGImageGetWidth:  %d\n"
//        @"CGImageGetColorSpace: %@\n"
//        @"CGImageGetBitsPerPixel:     %d\n"
//        @"CGImageGetBitsPerComponent: %d\n"
//        @"CGImageGetBytesPerRow:      %d\n"
//        @"CGImageGetBitmapInfo: 0x%.8X\n"
//        @"  kCGBitmapAlphaInfoMask     = %s\n"
//        @"  kCGBitmapFloatComponents   = %s\n"
//        @"  kCGBitmapByteOrderMask     = 0x%.8X\n"
//        @"  kCGBitmapByteOrderDefault  = %s\n"
//        @"  kCGBitmapByteOrder16Little = %s\n"
//        @"  kCGBitmapByteOrder32Little = %s\n"
//        @"  kCGBitmapByteOrder16Big    = %s\n"
//        @"  kCGBitmapByteOrder32Big    = %s\n",
//        (int)width,
//        (int)height,
//        CGImageGetColorSpace(cgimage),
//        (int)bpp,
//        (int)bpc,
//        (int)bpr,
//        (unsigned)info,
//        (info & kCGBitmapAlphaInfoMask)     ? "YES" : "NO",
//        (info & kCGBitmapFloatComponents)   ? "YES" : "NO",
//        (info & kCGBitmapByteOrderMask),
//        ((info & kCGBitmapByteOrderMask) == kCGBitmapByteOrderDefault)  ? "YES" : "NO",
//        ((info & kCGBitmapByteOrderMask) == kCGBitmapByteOrder16Little) ? "YES" : "NO",
//        ((info & kCGBitmapByteOrderMask) == kCGBitmapByteOrder32Little) ? "YES" : "NO",
//        ((info & kCGBitmapByteOrderMask) == kCGBitmapByteOrder16Big)    ? "YES" : "NO",
//        ((info & kCGBitmapByteOrderMask) == kCGBitmapByteOrder32Big)    ? "YES" : "NO"
//    );

    CGDataProviderRef provider = CGImageGetDataProvider(cgimage);
    NSData* data = (id)CFBridgingRelease(CGDataProviderCopyData(provider));
    //[data autorelease];
    const uint8_t* bytes = [data bytes];
    
    // single channel data for this here Channel object
    size_t wh = width * height;
    self->_data = (uint8_t*)malloc(bytes_per_pixel * wh);
    self->_width = width;
    self->_height = height;
    
    int smallerDim = (int)(MYMIN(width, height));
    //int taperSize = 14; //(int)(smallerDim * TAPER_RAT);
    
    // bytes is RGBA
    //size_t offset = 0;
    uint8_t* sd = self->_data;
    uint8_t* inp = (uint8_t *)bytes; //&bytes[row * bpr + col * bytes_per_pixel];
    for(size_t row = 0; row < height; row++) {
        for(size_t col = 0; col < width; col++) {
            uint8_t r = inp[0];
            uint8_t g = inp[1];
            uint8_t b = inp[2];
            uint8_t a = inp[3];
            uint8_t val = a;
//            if(shouldTaper) {
//                val = taper(val, taperSize, (int)width, (int)height, (int)col, (int)row);
//            }
            sd[0] = r;
            sd[1] = g;
            sd[2] = b;
            sd[3] = val;
            inp += bytes_per_pixel;
            sd += bytes_per_pixel;
        }
    }

    return self;
}

+ (CGImageRef)toImageWithArray:(NSArray<Masker *> *)maskerArray {
    NSUInteger n = [maskerArray count];
    if(n < 2) {
        printf("Expected to mask more than one image together.");
        return NULL;
    }
    size_t w = [[maskerArray objectAtIndex:0] width];
    size_t h = [[maskerArray objectAtIndex:0] height];
    //
    //make an array of pointers to all the decoded bytes, to avoid message passing in the inner loop
    uint8_t** buffers = (uint8_t**)malloc(sizeof(uint8_t*) * n);
    for(int i = 0; i < n; i++) {
        buffers[i] = [[maskerArray objectAtIndex:i] data];
    }
    //
    Masker* ret = [[Masker alloc] initWithWidth:w height:h];
    uint8_t* rd = ret->_data;
    size_t offset = 0;
    int taperSize = (int)(n * 2.0);
    for(int row = 0; row < h; row++) {
        for(int col = 0; col < w; col++) {
            uint8_t index = taper(n - 1, taperSize, (int)w, (int)h, col, row);
            index = MYCLAMP(index, 0, n - 1);
            uint8_t* inp = buffers[index];
            rd[offset + 0] = inp[offset + 0];
            rd[offset + 1] = inp[offset + 1];
            rd[offset + 2] = inp[offset + 2];
            rd[offset + 3] = 255;
            offset += BYTES_PER_PIXEL;
        }
    }
    return [ret toImage];
}

- (void)dealloc {
    //printf("dealloc called, for Channel with \%ld x \%ld data\n", self->_width, self->_height);
    if(self->_data) {
        free(self->_data);
        self->_data = NULL;
    }
    if(imageRef) {
        CGImageRelease(imageRef);
    }
}

@end

