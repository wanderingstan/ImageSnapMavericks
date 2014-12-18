//
//  main.m
//  ImageSnap
//
//  Created by Stan James on 12/18/14.
//
//

#define error(...) fprintf(stderr, __VA_ARGS__)
#define console(...) (!g_quiet && printf(__VA_ARGS__))
#define verbose(...) (g_verbose && !g_quiet && fprintf(stderr, __VA_ARGS__))

#include "ImageSnap.h"

BOOL g_verbose = NO;
BOOL g_quiet = NO;
NSString *VERSION = @"0.3.0";

// This is convoluted to handle the global variables and macros used.
// We create them above and then #include the actual ImageSnap.m file. Note that
// this file is NOT included in the compile sources for the project, but rather
// this main.m file is. We should find a better way to isolate these global
// element, or remove them.

#include "ImageSnap.m"

int processArguments(int argc, const char * argv[]);
void printUsage(int argc, const char * argv[]);
int listDevices();
NSString *generateFilename();
AVCaptureDevice *getDefaultDevice();


// Main entry point. Since we're using Cocoa and all kinds of fancy
// classes, we have to set up appropriate pools and loops.
// Thanks to the example http://lists.apple.com/archives/cocoa-dev/2003/Apr/msg01638.html
// for reminding me how to do it.
int main (int argc, const char * argv[]) {
    NSApplicationLoad();    // May be necessary for 10.5 not to crash.
    
    [NSApplication sharedApplication];
    
    int result = processArguments(argc, argv);
    
    return result;
}



/**
 * Process command line arguments and execute program.
 */
int processArguments(int argc, const char * argv[] ){
    
    NSString *filename = nil;
    AVCaptureDevice *device = nil;
    NSNumber *warmup = nil;
    NSNumber *timelapse = nil;
    
    
    int i;
    for( i = 1; i < argc; ++i ){
        
        // Handle command line switches
        if (argv[i][0] == '-') {
            
            // Dash only? Means write image to stdout
            if (argv[i][1] == 0 ){
                filename = @"-";
                g_quiet = YES;
            } else {
                
                // Which switch was given
                switch (argv[i][1]) {
                        
                        // Help
                    case '?':
                    case 'h':
                        printUsage( argc, argv );
                        return 0;
                        break;
                        
                        
                        // Verbose
                    case 'v':
                        g_verbose = YES;
                        break;
                        
                    case 'q':
                        g_quiet = YES;
                        break;
                        
                        
                        // List devices
                    case 'l':
                        listDevices();
                        return 0;
                        break;
                        
                        // Specify device
                    case 'd':
                        if (i+1 < argc ){
                            device = [ImageSnap deviceNamed:[NSString stringWithUTF8String:argv[i+1]]];
                            if (device == nil ){
                                error( "Device \"%s\" not found.\n", argv[i+1] );
                                return 11;
                            }   // end if: not found
                            ++i; // Account for "follow on" argument
                        } else {
                            error( "Not enough arguments given with 'd' flag.\n" );
                            return (int)'d';
                        }
                        break;
                        
                        // Specify a warmup period before picture snaps
                    case 'w':
                        if (i+1 < argc ){
                            warmup = [NSNumber numberWithFloat:[[NSString stringWithUTF8String:argv[i+1]] floatValue]];
                            ++i; // Account for "follow on" argument
                        } else {
                            error( "Not enough arguments given with 'w' flag.\n" );
                            return (int)'w';
                        }
                        break;
                        
                        // Timelapse
                    case 't':
                        if (i+1 < argc ){
                            timelapse = [NSNumber numberWithDouble:[[NSString stringWithUTF8String:argv[i+1]] doubleValue]];
                            //g_timelapse = [timelapse doubleValue];
                            ++i; // Account for "follow on" argument
                        } else {
                            error( "Not enough arguments given with 't' flag.\n" );
                            return (int)'t';
                        }
                        break;
                        
                        
                        
                }	// end switch: flag value
            }   // end else: not dash only
        }	// end if: '-'
        
        // Else assume it's a filename
        else {
            filename = [NSString stringWithUTF8String:argv[i]];
        }
        
    }	// end for: each command line argument
    
    
    // Make sure we have a filename
    if (filename == nil ){
        filename = generateFilename();
        verbose( "No filename specified. Using %s\n", [filename UTF8String] );
    }	// end if: no filename given
    
    if (filename == nil ){
        error( "No suitable filename could be determined.\n" );
        return 1;
    }
    
    
    // Make sure we have a device
    if (device == nil ){
        device = getDefaultDevice();
        verbose( "No device specified. Using %s\n", [[device description] UTF8String] );
    }	// end if: no device given
    
    if (device == nil ){
        error( "No video devices found.\n" );
        return 2;
    } else {
        console( "Capturing image from device \"%s\"...", [[device description] UTF8String] );
    }
    
    
    // Image capture
    if ([ImageSnap saveSnapshotFrom:device toFile:filename withWarmup:warmup withTimelapse:timelapse] ){
        console( "%s\n", [filename UTF8String] );
    } else {
        error( "Error.\n" );
    }   // end else
    
    return 0;
}



void printUsage(int argc, const char * argv[]){
    printf( "USAGE: %s [options] [filename]\n", argv[0] );
    printf( "Version: %s\n", [VERSION UTF8String] );
    printf( "Captures an image from a video device and saves it in a file.\n" );
    printf( "If no device is specified, the system default will be used.\n" );
    printf( "If no filename is specfied, snapshot.jpg will be used.\n" );
    printf( "Supported image types: JPEG, TIFF, PNG, GIF, BMP\n" );
    printf( "  -h          This help message\n" );
    printf( "  -v          Verbose mode\n");
    printf( "  -l          List available video devices\n" );
    printf( "  -t x.xx     Take a picture every x.xx seconds\n" );
    printf( "  -q          Quiet mode. Do not output any text\n");
    printf( "  -w x.xx     Warmup. Delay snapshot x.xx seconds after turning on camera\n" );
    printf( "  -d device   Use named video device\n" );
}





/**
 * Prints a list of video capture devices to standard out.
 */
int listDevices(){
    NSArray *devices = [ImageSnap videoDevices];
    
    [devices count] > 0
    ? printf("Video Devices:\n")
    : printf("No video devices found.\n");
    
    for( AVCaptureDevice *device in devices ){
        printf( "%s\n", [[device description] UTF8String] );
    }	// end for: each device
    return [devices count];
}

/**
 * Generates a filename for saving the image, presumably
 * because the user didn't specify a filename.
 * Currently returns snapshot.tiff.
 */
NSString *generateFilename(){
    NSString *result = @"snapshot.jpg";
    return result;
}	// end


/**
 * Gets a default video device, or nil if none is found.
 * For now, simply queries ImageSnap. May be fancier
 * in the future.
 */
AVCaptureDevice *getDefaultDevice(){
    return [ImageSnap defaultVideoDevice];
}	// end
