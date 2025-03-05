//
//  Masker.h
//  Mochi Diffusion
//
//  Created by Jared Updike on 3/4/25.
//

#ifndef Masker_h
#define Masker_h

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CGContext.h>

#define MYMAX(a, b)  (a > b ? a : b)
#define MYMIN(a, b)  (a < b ? a : b)
#define MYCLAMP(x, a, b)  (MYMAX(a, MYMIN(x, b)))

@interface Masker : NSObject {
    // private
    CGImageRef imageRef;
}
@property uint8_t* data;
@property size_t width, height;

- (id)initWithWidth:(size_t)w height:(size_t)h;

- (id)initWithColorImage:(CGImageRef)cgimage;
- (id)initWithTaperedColorImage:(CGImageRef)cgimage;

- (CGImageRef)toImage;

//- (id)initWithPgmPath:(NSString*)path;
//- (void)writeOutToPgmWithPath:(NSString*)path;

+ (CGImageRef)toImageWithArray:(NSArray<Masker *> *)maskerArray;

@end

#endif /* Masker_h */
