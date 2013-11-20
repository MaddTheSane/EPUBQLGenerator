#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>
#import <Cocoa/Cocoa.h>
#import "GNJUnZip.h"
#import "NSString+Additions.h"

/* -----------------------------------------------------------------------------
   Generate a thumbnail for file

   This function's job is to create thumbnail for designated file as fast as possible
   ----------------------------------------------------------------------------- */

OSStatus GenerateThumbnailForURL(void *thisInterface,
                                 QLThumbnailRequestRef thumbnail,
                                 CFURLRef url,
                                 CFStringRef contentTypeUTI,
                                 CFDictionaryRef options,
                                 CGSize maxSize)
{
  @autoreleasepool {

    NSString *path = [(__bridge NSURL *)url path];
    GNJUnZip *unzip = [[GNJUnZip alloc] initWithZipFile:path];

    NSCharacterSet *setForTrim = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    NSData *xmlData = [unzip dataWithContentsOfFile:@"META-INF/container.xml"];
    if(!xmlData) {
      return noErr;
    }

    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData
                                                        options:NSXMLDocumentTidyXML
                                                          error:NULL];
    if(!xmlDoc) {
      return noErr;
    }

    NSString *xpath = @"/container/rootfiles/rootfile/@full-path";
    NSArray *nodes = [xmlDoc nodesForXPath:xpath error:NULL];
    if(![nodes count]) {
      return noErr;
    }

    NSString *fullPathValue = [[nodes objectAtIndex:0] stringValue];
    NSString *opfFilePath = [fullPathValue stringByTrimmingCharactersInSet:setForTrim];
    opfFilePath = [opfFilePath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    xmlData = [unzip dataWithContentsOfFile:opfFilePath];
    if(!xmlData) {
      return noErr;
    }

    xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData
                                         options:NSXMLDocumentTidyXML
                                           error:NULL];
    if(!xmlDoc) {
      return noErr;
    }

    NSString *coverImagePath = nil;
    xpath = @"/package/manifest/item[contains(concat(' ', normalize-space(@properties), ' '), ' cover-image ')]/@href";
    nodes = [xmlDoc nodesForXPath:xpath error:NULL];
    if([nodes count]) coverImagePath = [[nodes objectAtIndex:0] stringValue];
    else {
      xpath = @"/package/metadata/meta[@name='cover']/@content";
      nodes = [xmlDoc nodesForXPath:xpath error:NULL];
      if([nodes count]) {
        NSString *coverImageId = [[[nodes objectAtIndex:0] stringValue] stringByTrimmingCharactersInSet:setForTrim];
        xpath = [NSString stringWithFormat:@"/package/manifest/item[@id='%@']/@href",
                 coverImageId];
        NSArray *coverImageItemHrefs = [xmlDoc nodesForXPath:xpath error:NULL];
        if([coverImageItemHrefs count]) {
          coverImagePath = [[coverImageItemHrefs objectAtIndex:0] stringValue];
        }
      }
    }

    if([coverImagePath length]) {
      coverImagePath = [coverImagePath stringByTrimmingCharactersInSet:setForTrim];
      coverImagePath = [coverImagePath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
      if([coverImagePath isAbsolutePath]) coverImagePath = [coverImagePath substringFromIndex:1];
      else {
        NSString *opfBasePath = [opfFilePath stringByDeletingLastPathComponent];
        coverImagePath = [opfBasePath stringByAppendingPathComponent:coverImagePath];
      }
      coverImagePath = [coverImagePath stringByForciblyResolvingSymlinksInPath];
      NSData *coverImageData = [unzip dataWithContentsOfFile:coverImagePath];
      NSImage *coverImage = [[NSImage alloc] initWithData:coverImageData];
      if([coverImage isValid]) {
        CGSize maximumSize = QLThumbnailRequestGetMaximumSize(thumbnail);
        NSSize imageSize = [coverImage size];
        CGFloat scale = maximumSize.width / ((imageSize.width > imageSize.height) ? imageSize.width : imageSize.height);
        NSSize newSize = NSMakeSize(imageSize.width * scale, imageSize.height * scale);
        NSImage *resizedImage = [[NSImage alloc] initWithSize:newSize];
        [resizedImage lockFocus];
        [coverImage drawInRect:NSMakeRect(0.0, 0.0, newSize.width, newSize.height)
                      fromRect:NSMakeRect(0.0, 0.0, imageSize.width, imageSize.height)
                     operation:NSCompositeSourceOver
                      fraction:1.0];
        [resizedImage unlockFocus];
        NSData *resizedImageData = [resizedImage TIFFRepresentation];
        QLThumbnailRequestSetImageWithData(thumbnail, (__bridge CFDataRef)resizedImageData, NULL);
      }
    }


    return noErr;
  }
}

void CancelThumbnailGeneration(void* thisInterface,
                               QLThumbnailRequestRef thumbnail)
{
  // implement only if supported
}
