//
//  HeightViewController.m
//  Go Map!!
//
//  Created by Bryce on 11/19/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <sys/utsname.h>
#import <CoreMotion/CoreMotion.h>


#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "HeightViewController.h"
#import "MapView.h"
#import "OsmObjects.h"
#import "VectorMath.h"


@interface HeightViewController ()
@end


@implementation HeightViewController

- (void)viewDidLoad
{
	_rulerViews	 = [NSMutableDictionary new];
	_rulerLayers = [NSMutableDictionary new];

	[self startCameraPreview];

	_coreMotion = [CMMotionManager new];
	[_coreMotion setDeviceMotionUpdateInterval:1.0/30];
	NSOperationQueue *currentQueue = [NSOperationQueue currentQueue];
	__weak HeightViewController * weakSelf = self;
	[_coreMotion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXTrueNorthZVertical
														toQueue:currentQueue
													withHandler:^(CMDeviceMotion *motion, NSError *error) {
														[weakSelf refreshRulerLabels:motion];
													}];

	_doneButton.layer.cornerRadius	= 5;
	_doneButton.layer.borderColor	= [UIColor blueColor].CGColor;
	_doneButton.layer.borderWidth	= 2.0;

	_distanceLabel.backgroundColor			= nil;
	_distanceLabel.layer.cornerRadius		= 5;
	_distanceLabel.layer.backgroundColor	= [UIColor colorWithRed:0.6 green:0.6 blue:1.0 alpha:0.5].CGColor;

	_scrollPosition = 20;
	
	UIGestureRecognizer * tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTap:)];
	[self.view addGestureRecognizer:tap];

	UIGestureRecognizer * pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(didPan:)];
	[self.view addGestureRecognizer:pan];
}



-(BOOL)startCameraPreview
{
	_captureSession = [[AVCaptureSession alloc] init];

	AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if ( videoDevice == nil )
		return NO;
	NSError *error;
	AVCaptureDeviceInput * videoIn = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	if ( error )
		return NO;
	if ( ![_captureSession canAddInput:videoIn] )
		return NO;
	[_captureSession addInput:videoIn];


	// get FOV
	_cameraFOV = videoDevice.activeFormat.videoFieldOfView;
	if ( _cameraFOV == 0 ) {
		_cameraFOV = [self cameraFOV];
	}
	_cameraFOV *= M_PI/180;


	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
	_previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

	_previewLayer.bounds = self.view.layer.bounds;
	_previewLayer.position = CGRectCenter(self.view.layer.bounds);
	_previewLayer.zPosition = -1;	// buttons and labels need to be above video
	[self.view.layer addSublayer:_previewLayer];

	[_captureSession startRunning];

	return YES;
}

-(void)didTap:(UITapGestureRecognizer *)tap
{
	CGPoint pos = [tap locationInView:self.view];
	AVCaptureDeviceInput * input = _captureSession.inputs.lastObject;
	NSError * error = nil;
	[input.device lockForConfiguration:&error];
	if ( error == nil ) {
		CGRect rc = self.view.bounds;
		pos.x = (pos.x - rc.origin.x) / rc.size.width;
		pos.y = (pos.y - rc.origin.y) / rc.size.height;
		input.device.exposurePointOfInterest = pos;
		[input.device unlockForConfiguration];
	}
}

-(void)didPan:(UIPanGestureRecognizer *)pan
{
	CGPoint delta = [pan translationInView:self.view];
	_scrollPosition -= delta.y;
	[pan setTranslation:CGPointMake(0,0) inView:self.view];
}

- (NSUInteger)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskPortrait;
}
-(BOOL)shouldAutorotate
{
	return NO;
}

-(double)cameraFOV
{
	static double cameraAngle = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		// field of view = f( resolution, focal length, chip size )
		// angle = 2*atan2(vertical_sensor_size/2,focal length) * 180 / 3.14159

		static struct {
			char *	model;
			double	fov;
			double	focal_length;
			double	vertical_sensor_size;
		} ModelList[] = {
			// http://caramba-apps.com/blog/files/field-of-view-angles-ipad-iphone.html

			{ "iPad5,4",	0, 3.3, 0 },		// iPad Air 2
			{ "iPad4,5",	0 },				// iPad Mini (2nd Generation iPad Mini - Cellular)
			{ "iPad4,4",	0 },				// iPad Mini (2nd Generation iPad Mini - Wifi)
			{ "iPad4,2",	0 },				// iPad Air 5th Generation iPad (iPad Air) - Cellular
			{ "iPad4,1",	0 },				// iPad Air 5th Generation iPad (iPad Air) - Wifi
			{ "iPad3,6",	0 },				// iPad 4 (4th Generation)
			{ "iPad3,5",	0 },				// iPad 4 (4th Generation)
			{ "iPad3,4",	0 },				// iPad 4 (4th Generation)
			{ "iPad3,3",	0 },				// iPad 3 (3rd Generation)
			{ "iPad3,2",	0 },				// iPad 3 (3rd Generation)
			{ "iPad3,1",	0 },				// iPad 3 (3rd Generation)
			{ "iPad2,7",	0 },				// iPad Mini (Original)
			{ "iPad2,6",	0 },				// iPad Mini (Original)
			{ "iPad2,5",	0, 3.3, 0 },				// iPad Mini (Original)
			{ "iPad2,4",	43.47 },				// iPad 2
			{ "iPad2,3",	43.47 },				// iPad 2
			{ "iPad2,2",	43.47 },				// iPad 2
			{ "iPad2,1",	43.47 },				// iPad 2

			{ "iPhone7,2",	0, 4.15, 4.89 },				// iPhone 6+
			{ "iPhone7,1",	0, 4.15, 4.89 },				// iPhone 6
			{ "iPhone6,2",	0, 4.12, 4.89 },				// iPhone 5s (model A1457, A1518, A1528 (China), A1530 | Global)
			{ "iPhone6,1",	0, 4.12, 4.89 },				// iPhone 5s model A1433, A1533 | GSM)
			{ "iPhone5,4",	0, 4.10, 4.54 },				// iPhone 5c (model A1507, A1516, A1526 (China), A1529 | Global)
			{ "iPhone5,3",	0, 4.10, 4.54 },				// iPhone 5c (model A1456, A1532 | GSM)
			{ "iPhone5,2",	58.498, 4.10, 4.592 },				// iPhone 5 (model A1429, everything else)
			{ "iPhone5,1",	58.498, 4.10, 4.592 },				// iPhone 5 (model A1428, AT&T/Canada)
			{ "iPhone4,1",	56.423, 4.28, 4.592 },				// iPhone 4S
			{ "iPhone3,1",	61.048, 3.85, 4.54 },				// iPhone 4
			{ "iPhone2,1",	49.871, 3.85, 3.58 },				// iPhone 3GS
			{ "iPhone1,1",	49.356, 3.85, 3.538 },				// iPhone 3

			{ "iPod4,1",	0 },				// iPod Touch (Fifth Generation)
			{ "iPod4,1",	0 },				// iPod Touch (Fourth Generation)
		};

		struct utsname systemInfo = { 0 };
		uname(&systemInfo);
		for ( int i = 0; i < sizeof ModelList/sizeof ModelList[0]; ++i ) {
			if ( ModelList[i].vertical_sensor_size == 0 )
				continue;
			if ( ModelList[i].focal_length == 0 )
				continue;
			double a = 2*atan2(ModelList[i].vertical_sensor_size/2,ModelList[i].focal_length) * 180 / M_PI;
			assert( ModelList[i].fov == 0 || fabs(a - ModelList[i].fov) < 0.01 );
			if ( strcmp( systemInfo.machine, ModelList[i].model ) == 0 ) {
				cameraAngle = a;
			}
		}

		if ( cameraAngle == 0 )
			cameraAngle = 58.498;	// wild guess
	});
	return cameraAngle;
}


-(double)distanceToObject:(double *)error direction:(double *)pDirection
{
	AppDelegate			*	delegate = [[UIApplication sharedApplication] delegate];
	CLLocation			*	location = delegate.mapView.currentLocation;
	CLLocationCoordinate2D	userLoc = location.coordinate;
	OsmBaseObject		*	object	= delegate.mapView.editorLayer.selectedPrimary;
	OSMPoint				userPt	= { userLoc.longitude, userLoc.latitude };

	double dist = MAXFLOAT;
	double bearing = 0;
	for ( OsmNode * node in object.nodeSet ) {
		OSMPoint nodePt = { node.lon, node.lat };
		double d = GreatCircleDistance( userPt, nodePt );
		if ( d < dist ) {
			dist = d;
			OSMPoint dir = { lat2latp(nodePt.y) - lat2latp(userPt.y), nodePt.x - userPt.x };
			dir = UnitVector(dir);
			bearing = atan2( dir.y, dir.x );
		}
	}
	*error		= location.horizontalAccuracy;
	*pDirection	= bearing;

	return dist;
}

-(NSString *)distanceStringForFloat:(double)num
{
	if ( num < 10 )
		return [NSString stringWithFormat:@"%.1f",num];
	else
		return [NSString stringWithFormat:@"%.0f",num];
}


-(void)refreshRulerLabels:(CMDeviceMotion *)motion
{
	if ( _isExiting )
		return;

	// compute location
	const CGFloat labelBorderWidth = 5;
	double distError = 0;
	double direction = 0;
	double dist = [self distanceToObject:&distError direction:&direction];

	// get camera tilt
	double pitch = motion.attitude.pitch;
	double yaw	 = motion.attitude.yaw;
	if ( fabs(yaw - direction) < M_PI/2 ) {
		pitch = M_PI/2 - pitch;
	} else {
		pitch = pitch - M_PI/2;
	}

	double userHeight = tan( _cameraFOV/2 - pitch ) * dist;

	// update distance label
	_distanceLabel.text = [NSString stringWithFormat:@"Distance: %@ m ± %@", [self distanceStringForFloat:dist], [self distanceStringForFloat:distError]];
	CGPoint pos = _distanceLabel.center;
	[_distanceLabel sizeToFit];
	_distanceLabel.bounds = CGRectInset( _distanceLabel.bounds, -labelBorderWidth, 0);
	_distanceLabel.center = pos;

	// get number of labels to display
	double maxHeight = dist*tan( _cameraFOV/2 + pitch ) + dist*tan( _cameraFOV/2 - pitch );
	double increment = 0.1;
	int scale = 1;
	while ( maxHeight / increment > 10 ) {
		if ( scale == 1 ) {
			scale = 2;
			increment *= 2;
		} else if ( scale == 2 ) {
			scale = 5;
			increment *= 2.5;
		} else {
			scale = 1;
			increment *= 2;
		}
	}


	CGRect rc = self.view.bounds;
	double dist2 = (rc.size.height/2) / tan(_cameraFOV/2);

	double scrollHeight = _scrollPosition * dist/dist2;

	for ( NSInteger div = -20; div < 30; ++div ) {
		double labelHeight = div * increment * 0.5;
		double height = labelHeight + scrollHeight;

		double angleRelativeToGround = atan2( height - userHeight, dist );
		double centerAngleOffset = angleRelativeToGround - pitch;

		double delta = tan(centerAngleOffset) * dist2;
		double pixels = round( rc.size.height/2 - delta );

		CGFloat labelWidth = 0;
		if ( div % 2 == 0 ) {
			UILabel * label = _rulerViews[ @(div) ];
			if ( label == nil ) {
				label = [[UILabel alloc] init];
				[_rulerViews setObject:label forKey:@(div)];
			}
			if ( pixels > rc.size.height || pixels < 0 ) {
				[label removeFromSuperview];
			} else {
				label.layer.anchorPoint = CGPointMake(0, 0.5);
				label.text				= [NSString stringWithFormat:@"%@ meters", [self distanceStringForFloat:height-scrollHeight]];
				label.font				= [UIFont systemFontOfSize:16];
				label.backgroundColor	= [UIColor colorWithWhite:1.0 alpha:0.5];
				label.textColor			= [UIColor blackColor];
				label.textAlignment		= NSTextAlignmentCenter;
				[label sizeToFit];
				label.bounds			= CGRectInset( label.bounds, -labelBorderWidth, 0);
				label.center			= CGPointMake( 0, pixels );
				labelWidth				= label.bounds.size.width;
				if ( label.superview == nil )
					[self.view addSubview:label];
				}
		}

		CAShapeLayer * layer = _rulerLayers[ @(div) ];
		if ( layer == nil ) {
			layer = [CAShapeLayer new];
			[_rulerLayers setObject:layer forKey:@(div)];
		}
		if ( pixels > rc.size.height || pixels < 0 ) {
			[layer removeFromSuperlayer];
		} else {
			UIBezierPath * path = [[UIBezierPath alloc] init];
			BOOL isZero = div == 0;
			[path moveToPoint:CGPointMake( labelWidth, pixels)];
			[path addLineToPoint:CGPointMake(rc.size.width, pixels)];
			layer.path = path.CGPath;
			layer.strokeColor = isZero ? [UIColor greenColor].CGColor : [UIColor whiteColor].CGColor;
			layer.lineWidth = isZero ? 2 : 1;
			layer.frame = self.view.bounds;
			if ( div % 2 == 1 ) {
				layer.lineDashPattern = @[ @5, @4 ];
			}
			if ( layer.superlayer == nil )
				[self.view.layer addSublayer:layer];
		}
	}
}


-(IBAction)done:(id)sender
{
	_isExiting = YES;
	[_captureSession stopRunning];
	[_coreMotion stopDeviceMotionUpdates];

	for ( UIView * v in [self.view.subviews copy] ) {
		[v removeFromSuperview];
	}
	self.view.layer.sublayers = nil;

	[self dismissViewControllerAnimated:YES completion:^{
	}];
}

@end
