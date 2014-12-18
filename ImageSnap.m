//
//  ImageSnap.m
//  ImageSnap
//
//  Created by Robert Harder on 9/10/09.
//  Updated by Sam Green for Mavericks (OSX 10.9) on 11/22/13
//  Updated by Stan James for ARC on 2013-12-18
//

#import "ImageSnap.h"

#define error(...) fprintf(stderr, __VA_ARGS__)
#define console(...) (!g_quiet && printf(__VA_ARGS__))
#define verbose(...) (g_verbose && !g_quiet && fprintf(stderr, __VA_ARGS__))

BOOL g_verbose = NO;
BOOL g_quiet = NO;

@interface ImageSnap ()

/**
 * Writes an NSImage to disk, formatting it according
 * to the file extension. If path is "-" (a dash), then
 * an jpeg representation is written to standard out.
 */
+ (BOOL)saveImage:(NSImage *)image toPath:(NSString *)path;

/**
 * Converts an NSImage to raw NSData according to a given
 * format. A simple string search is performed for such
 * characters as jpeg, tiff, png, and so forth.
 */
+ (NSData *)dataFrom:(NSImage *)image asType:(NSString *)format;

@property (strong, nonatomic) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureDeviceInput *input;
@property (strong, nonatomic) AVCaptureVideoDataOutput *output;

@end


@implementation ImageSnap

- (id)init {
	self = [super init];
    if (self) {
        _session = nil;
        _input = nil;
        _output = nil;
        
        mCurrentImageBuffer = nil;
    }
	return self;
}

- (void)dealloc {
    _session = nil;
    _input = nil;
    _output = nil;
    
    CVBufferRelease(mCurrentImageBuffer);
}

// Returns an array of video devices attached to this computer.
+ (NSArray *)videoDevices {
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:3];
    [results addObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]];
    [results addObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]];
    return results;
}

// Returns the default video device or nil if none found.
+ (AVCaptureDevice *)defaultVideoDevice {
	AVCaptureDevice *device = nil;
    
    device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if (device == nil ){
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeMuxed];
	}
    return device;
}

// Returns the named capture device or nil if not found.
+ (AVCaptureDevice *)deviceNamed:(NSString *)name {
    AVCaptureDevice *result = nil;
    
    NSArray *devices = [ImageSnap videoDevices];
	for( AVCaptureDevice *device in devices ){
        if ( [name isEqualToString:[device description]] ){
            result = device;
        }   // end if: match
    }   // end for: each device
    
    return result;
}   // end


// Saves an image to a file or standard out if path is nil or "-" (hyphen).
+ (BOOL)saveImage:(NSImage *)image toPath:(NSString *)path {
    
    NSString *ext = [path pathExtension];
    NSData *photoData = [ImageSnap dataFrom:image asType:ext];
    
    // If path is a dash, that means write to standard out
    if (path == nil || [@"-" isEqualToString:path] ){
        NSUInteger length = [photoData length];
        NSUInteger i;
        char *start = (char *)[photoData bytes];
        for( i = 0; i < length; ++i ){
            putc( start[i], stdout );
        }   // end for: write out
        return YES;
    } else {
        return [photoData writeToFile:path atomically:NO];
    }
    
    
    return NO;
}


/**
 * Converts an NSImage into NSData. Defaults to jpeg if
 * format cannot be determined.
 */
+ (NSData *)dataFrom:(NSImage *)image asType:(NSString *)format {
    
    NSData *tiffData = [image TIFFRepresentation];
    
    NSBitmapImageFileType imageType = NSJPEGFileType;
    NSDictionary *imageProps = nil;
    
    
    // TIFF. Special case. Can save immediately.
    if ([@"tif"  rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ||
       [@"tiff" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ){
        return tiffData;
    }
    
    // JPEG
    else if ([@"jpg"  rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [@"jpeg" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ){
        imageType = NSJPEGFileType;
        imageProps = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:0.9] forKey:NSImageCompressionFactor];
        
    }
    
    // PNG
    else if ([@"png" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ){
        imageType = NSPNGFileType;
    }
    
    // BMP
    else if ([@"bmp" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ){
        imageType = NSBMPFileType;
    }
    
    // GIF
    else if ([@"gif" rangeOfString:format options:NSCaseInsensitiveSearch].location != NSNotFound ){
        imageType = NSGIFFileType;
    }
    
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:tiffData];
    NSData *photoData = [imageRep representationUsingType:imageType properties:imageProps];
    
    return photoData;
}   // end dataFrom



/**
 * Primary one-stop-shopping message for capturing an image.
 * Activates the video source, saves a frame, stops the source,
 * and saves the file.
 */

+ (BOOL)saveSnapshotFrom:(AVCaptureDevice *)device toFile:(NSString *)path {
    return [self saveSnapshotFrom:device toFile:path withWarmup:nil];
}

+ (BOOL)saveSnapshotFrom:(AVCaptureDevice *)device toFile:(NSString *)path withWarmup:(NSNumber *)warmup {
    return [self saveSnapshotFrom:device toFile:path withWarmup:warmup withTimelapse:nil];
}

+ (BOOL)saveSnapshotFrom:(AVCaptureDevice *)device
                 toFile:(NSString *)path
             withWarmup:(NSNumber *)warmup
          withTimelapse:(NSNumber *)timelapse {
    ImageSnap *snap;
    NSImage *image = nil;
    double interval = timelapse == nil ? -1 : [timelapse doubleValue];
    
    snap = [[ImageSnap alloc] init];            // Instance of this ImageSnap class
    verbose("Starting device...");
    if ([snap startSession:device] ){           // Try starting session
        verbose("Device started.\n");
        
        if (warmup == nil ){
            // Skip warmup
            verbose("Skipping warmup period.\n");
        } else {
            double delay = [warmup doubleValue];
            verbose("Delaying %.2lf seconds for warmup...",delay);
            NSDate *now = [[NSDate alloc] init];
            [[NSRunLoop currentRunLoop] runUntilDate:[now dateByAddingTimeInterval: [warmup doubleValue]]];
            now = nil;
            verbose("Warmup complete.\n");
        }
        
        if ( interval > 0 ) {
            
            verbose("Time lapse: snapping every %.2lf seconds to current directory.\n", interval);
            
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss.SSS"];
            
            // wait a bit to make sure the camera is initialized
            //[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 1.0]];
            
            for (unsigned long seq=0; ; seq++)
            {
                NSDate *now = [[NSDate alloc] init];
                NSString *nowstr = [dateFormatter stringFromDate:now];
                
                verbose(" - Snapshot %5lu", seq);
                verbose(" (%s)\n", [nowstr UTF8String]);
                
                // create filename
                NSString *filename = [NSString stringWithFormat:@"snapshot-%05lu-%s.jpg", seq, [nowstr UTF8String]];
                
                // capture and write
                image = [snap snapshot];                // Capture a frame
                if (image != nil)  {
                    [ImageSnap saveImage:image toPath:filename];
                    console( "%s\n", [filename UTF8String]);
                } else {
                    error( "Image capture failed.\n" );
                }
                
                // sleep
                [[NSRunLoop currentRunLoop] runUntilDate:[now dateByAddingTimeInterval: interval]];
                
                now = nil;
            }
            
        } else {
            image = [snap snapshot];                // Capture a frame
            
        }
        //NSLog(@"Stopping...");
        [snap stopSession];                     // Stop session
        //NSLog(@"Stopped.");
    }   // end if: able to start session
    
    snap = nil;
    
    if ( interval > 0 ){
        return YES;
    } else {
        return image == nil ? NO : [ImageSnap saveImage:image toPath:path];
    }
}   // end


/**
 * Returns current snapshot or nil if there is a problem
 * or session is not started.
 */
- (NSImage *)snapshot{
    verbose( "Taking snapshot...\n");
	
    CVImageBufferRef frame = nil;               // Hold frame we find
    while( frame == nil ){                      // While waiting for a frame
		
		//verbose( "\tEntering synchronized block to see if frame is captured yet...");
        @synchronized(self){                    // Lock since capture is on another thread
            frame = mCurrentImageBuffer;        // Hold current frame
            CVBufferRetain(frame);              // Retain it (OK if nil)
        }   // end sync: self
		//verbose( "Done.\n" );
		
        if (frame == nil ){                     // Still no frame? Wait a little while.
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 0.1]];
        }   // end if: still nothing, wait
		
    }   // end while: no frame yet
    
    // Convert frame to an NSImage
    NSCIImageRep *imageRep = [NSCIImageRep imageRepWithCIImage:[CIImage imageWithCVImageBuffer:frame]];
    NSImage *image = [[NSImage alloc] initWithSize:[imageRep size]];
    [image addRepresentation:imageRep];
	verbose( "Snapshot taken.\n" );
    
    return image;
}




/**
 * Blocks until session is stopped.
 */
-(void)stopSession{
	verbose("Stopping session...\n" );
    
    // Make sure we've stopped
    while( _session != nil ){
		verbose("\tCaptureSession != nil\n");
        
		verbose("\tStopping CaptureSession...");
        [_session stopRunning];
		verbose("Done.\n");
        
        if ([_session isRunning] ){
			verbose( "[mCaptureSession isRunning]");
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 0.1]];
        }else {
            verbose( "\tShutting down 'stopSession(..)'" );
            _session = nil;
            _input = nil;
            _output = nil;
        }   // end if: stopped
        
    }   // end while: not stopped
}


/**
 * Begins the capture session. Frames begin coming in.
 */
-(BOOL)startSession:(AVCaptureDevice *)device {
	
	verbose( "Starting capture session...\n" );
	
    if (device == nil ) {
		verbose( "\tCannot start session: no device provided.\n" );
		return NO;
	}
    
    // If we've already started with this device, return
    if ([device isEqual:[_input device]] &&
       _session != nil &&
       [_session isRunning] ){
        return YES;
    }   // end if: already running
	
    else if (_session != nil ){
		verbose( "\tStopping previous session.\n" );
        [self stopSession];
    }   // end if: else stop session
    
	
	// Create the capture session
	verbose( "\tCreating AVCaptureSession..." );
    _session = [[AVCaptureSession alloc] init];
    _session.sessionPreset = AVCaptureSessionPresetHigh;
	verbose( "Done.\n");
	
	// Create input object from the device
	verbose( "\tCreating AVCaptureDeviceInput with %s...", [[device description] UTF8String] );
	_input = [AVCaptureDeviceInput deviceInputWithDevice:device error:NULL];
	verbose( "Done.\n");
    [_session addInput:_input];
	
	// Decompressed video output
	verbose( "\tCreating AVCaptureDecompressedVideoOutput...");
    _output = [[AVCaptureVideoDataOutput alloc] init];
    _output.videoSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    
    // Add sample buffer serial queue
    dispatch_queue_t queue = dispatch_queue_create("VideoCaptureQueue", NULL);
    [_output setSampleBufferDelegate:self queue:queue];
    dispatch_release(queue);
	verbose( "Done.\n" );
    [_session addOutput:_output];
    
    // Clear old image?
	verbose("\tEntering synchronized block to clear memory...");
    @synchronized(self){
        if (mCurrentImageBuffer != nil ){
            CVBufferRelease(mCurrentImageBuffer);
            mCurrentImageBuffer = nil;
        }
    }
	verbose( "Done.\n");
    
	[_session startRunning];
	verbose("Session started.\n");
    
    return YES;
}


#pragma mark - AVCaptureVideoDataOutput Delegate
// This delegate method is called whenever the AVCaptureVideoOutput receives frame
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    // Swap out old frame for new one
    CVImageBufferRef videoFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVBufferRetain(videoFrame);
    
    CVImageBufferRef imageBufferToRelease;
    @synchronized(self){
        imageBufferToRelease = mCurrentImageBuffer;
        mCurrentImageBuffer = videoFrame;
    }   // end sync
    CVBufferRelease(imageBufferToRelease);
}

@end


