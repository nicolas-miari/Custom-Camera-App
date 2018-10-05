//
//  CameraViewController.swift
//  CustomCamera
//
//  Created by Nicolás Miari on 2018/09/26.
//  Copyright © 2018 Nicolás Miari. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

/**
 Most of the video capture code is based on Apple's sample code ["App-iOS"](https://developer.apple.com/library/archive/samplecode/App/Introduction/Intro.html#//apple_ref/doc/uid/DTS40010112).
 Major changes are detailed in the discussion below.

 ### Supported Media Types

 This implementation removes from the original sample code all pieces pertaining
 to recording video or live photos (the app only supports still photo capture).

 ### Image Orientation Architecture

 The original app supports autorotation: Whenever the view size changes, the new
 device orientation is queried and used to update the `videoOrientation`
 property of the preview layer's capture connection, which is then passed along
 to the **photo output** connection just before capture occurs.

 However, with such setup it is impossible to implement user interface elements
 (buttons, thumbnails) that "rotate but stay in place", as seen in (e.g.) the
 stock Camera app. Instead, autorotation support is dropped and the view
 controller remains in the **portrait** interface orientation all along. When
 photo capture is about to occur, the **device** orientation is queried and used
 to directly adjust the `videoOrientation` property of the photo output
 connection.
 */
class CameraViewController: UIViewController {

    // Displays live video feed from the camera (view finder)
    @IBOutlet private(set) weak var previewView: PreviewView!

    // Toggle between front and back camera
    @IBOutlet private(set) weak var cameraButton: UIButton!

    // Snap photo
    @IBOutlet private weak var photoButton: UIButton!

    //

    private var photoButtonCenter: CGPoint = .zero

    private let session = AVCaptureSession()

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        // Disable UI. The UI is enabled if and only if the session starts running.
        setUserInterfaceEnabled(false)

        // Set up the video preview view.
        previewView.session = session

        /*
         Check video authorization status. Video access is required and audio
         access is optional. If audio access is denied, audio is not recorded
         during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break

        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. We suspend the session queue to delay session
             setup until the access request has completed.

             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })

        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }

        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.

         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning

            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "App doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "App", message: message, preferredStyle: .alert)

                    alertController.addAction(
                        UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                        style: .cancel,
                        handler: nil))

                    alertController.addAction(
                        UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                        style: .`default`,
                        handler: { _ in
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: convertToUIApplicationOpenExternalURLOptionsKeyDictionary([:]), completionHandler: nil)
                        }
                    ))
                    self.present(alertController, animated: true, completion: nil)
                }

            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "App", message: message, preferredStyle: .alert)

                    alertController.addAction(
                        UIAlertAction(
                            title: NSLocalizedString("OK", comment: "Alert OK button"),
                            style: .cancel,
                            handler: nil))
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.orientationChanged(_:)),
            name: NSNotification.Name(rawValue: "orientationWillChange"),
            object: nil)
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        // kick off notification of current orientation.
        appDelegate.getInitialOrientation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        super.viewWillDisappear(animated)
    }

    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation


            coordinator.animate(alongsideTransition: { (context) in
                let deltaTransform = coordinator.targetTransform
                let deltaAngle = atan2(deltaTransform.b, deltaTransform.a)
                var currentRotation = self.photoButton.layer.value(forKeyPath: "transform.rotation.z") as! CGFloat
                currentRotation += -1 * deltaAngle + 0.0001
                self.photoButton.layer.setValue(currentRotation, forKeyPath: "transform.rotation.z")

            }, completion: {(context) in

                var currentTransform = self.photoButton.transform
                currentTransform.a = round(currentTransform.a)
                currentTransform.b = round(currentTransform.b)
                currentTransform.c = round(currentTransform.c)
                currentTransform.d = round(currentTransform.d)

                self.photoButton.transform = currentTransform
            })
        }
    }

    // MARK: - Custom Orientation Support

    @objc func orientationChanged(_ notification: NSNotification ){
        guard let userInfo = notification.userInfo as? [String: NSNumber] else {
            return
        }
        guard let orientationValue = userInfo["orientation"] else {
            return
        }
        guard let deviceOrientation = UIDeviceOrientation(rawValue: orientationValue.intValue) else {
            return
        }
        rotateSubviews(for: deviceOrientation)
    }

    private func rotateSubviews(for orientation: UIDeviceOrientation) {
        let angle: CGFloat = {
            switch orientation {
            case .landscapeLeft:
                return (CGFloat.pi/2)
            case .landscapeRight:
                return (3*CGFloat.pi/2)
            case .portrait:
                return 0
            case .portraitUpsideDown:
                return CGFloat.pi
            default:
                return 0
            }
        }()

        let newTransform = CGAffineTransform(rotationAngle: angle)
        UIView.animate(withDuration: 0.2, animations: {
            self.photoButton.transform = newTransform
            self.cameraButton.transform = newTransform
        })
    }

    private func correctedVideoOrientation(for deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case UIDeviceOrientation.portrait, .faceUp:
            return AVCaptureVideoOrientation.portrait
        case UIDeviceOrientation.portraitUpsideDown, .faceDown:
            return AVCaptureVideoOrientation.portraitUpsideDown
        case UIDeviceOrientation.landscapeLeft:
            return AVCaptureVideoOrientation.landscapeRight
        case UIDeviceOrientation.landscapeRight:
            return AVCaptureVideoOrientation.landscapeLeft
        case UIDeviceOrientation.unknown:
            return AVCaptureVideoOrientation.portrait
        }
    }

    // MARK: - Session Management

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    private var isSessionRunning = false

    private let sessionQueue = DispatchQueue(label: "session queue") // Communicate with the session and other session objects on this queue.

    private var setupResult: SessionSetupResult = .success

    var videoDeviceInput: AVCaptureDeviceInput!

    // Call this on the session queue.
    private func configureSession() {
        if setupResult != .success {
            return
        }
        session.beginConfiguration()

        /*
         We do not create an AVCaptureMovieFileOutput when setting up the
         session because the AVCaptureMovieFileOutput does not support movie
         recording with AVCaptureSession.Preset.photo.
         */
        session.sessionPreset = .photo

        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?

            // Choose the back dual camera if available, otherwise default to a wide angle camera.
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If the back dual camera is not available, default to the back wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                /*
                 In some cases where users break their phones, the back wide
                 angle camera is not available. In this case, we should default
                 to the front wide angle camera.
                 */
                defaultVideoDevice = frontCameraDevice
            }

            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput

                DispatchQueue.main.async {
                    /*
                     Why are we dispatching this to the main queue?
                     Because AVCaptureVideoPreviewLayer is the backing layer for
                     PreviewView and UIView can only be manipulated on the main
                     thread.
                     Note: As an exception to the above rule, it is not
                     necessary to serialize video orientation changes on the
                     AVCaptureVideoPreviewLayer’s connection with other session
                     manipulation.

                     Use the status bar orientation as the initial video
                     orientation. Subsequent orientation changes are handled by
                     CameraViewController.viewWillTransition(to:with:).

                     UPDATE:
                     Video preview layer is always in portrait orientation.
                     Adjustments are instead performed on the photo output
                     connection at the moment of capture, and
                     viewWillTransition(to:with:) is never called because the
                     view controller only supports portrait.
                     */
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = .portrait
                }
            } else {
                print("Could not add video device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        // Add photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported

        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
    }

    //

    private func setUserInterfaceEnabled(_ enabled: Bool) {
        cameraButton.isEnabled = enabled
        photoButton.isEnabled = enabled
    }

    // MARK: Device Configuration

    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera],
        mediaType: .video,
        position: .unspecified)

    @IBAction private func changeCamera(_ cameraButton: UIButton) {
        setUserInterfaceEnabled(false)

        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position

            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType

            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera

            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInWideAngleCamera
            }

            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil

            // First, look for a device with both the preferred position and device type. Otherwise, look for a device with only the preferred position.
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }

            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

                    self.session.beginConfiguration()

                    /*
                     Remove the existing device input first, since using the
                     front and back camera simultaneously is not supported.
                     */
                    self.session.removeInput(self.videoDeviceInput)

                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)

                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)

                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }

                    self.session.commitConfiguration()
                } catch {
                    print("Error occured while creating video device input: \(error)")
                }
            }

            DispatchQueue.main.async {
                self.setUserInterfaceEnabled(true)
            }
        }
    }

    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }

    private func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()

                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate
                 a (focus/exposure) operation. Call set(Focus/Exposure)Mode() to
                 apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }

                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }

    // MARK: Capturing Photos

    private let photoOutput = AVCapturePhotoOutput()

    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()

    @IBAction private func capturePhoto(_ photoButton: UIButton) {
        /*
         This view controller and its views/layers do not rotate. Instead of
         using the preview layer's videeo orientation, retrieve the DEVICE
         orientation, and derive an appropriate capture video orientation for
         the photo output capture connection.
         */
        let deviceOrientation = UIDevice.current.orientation
        let videoOrientation = correctedVideoOrientation(for: deviceOrientation)

        sessionQueue.async {
            /*
             Update the photo output's connection so it is consistent with the
             device's orientation
             */
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoOrientation
            }

            var photoSettings = AVCapturePhotoSettings()

            /*
             Capture HEIF photo when supported, with flash set to auto and high
             resolution photo enabled.
             */
            if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = .auto
            }
            photoSettings.isHighResolutionPhotoEnabled = true
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }

            /*
             Use a separate object for the photo capture delegate to isolate
             each capture life cycle.
             */
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                DispatchQueue.main.async {
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, completionHandler: { photoCaptureProcessor in
                /*
                 When the capture is complete, remove a reference to the photo
                 capture delegate so it can be deallocated.
                 */
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            })

            /*
             The Photo Output keeps a weak reference to the photo capture
             delegate so we store it in an array to maintain a strong reference
             to this object until the capture is completed.
             */
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }

    // MARK: KVO and Notifications

    private var keyValueObservations = [NSKeyValueObservation]()

    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else {
                return
            }
            DispatchQueue.main.async {
                /*
                 Only enable the ability to change camera if the device has more
                 than one camera.
                 */
                self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.photoButton.isEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)

        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
        notificationCenter.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)

        /*
         A session can only run when the app is full screen. It will be
         interrupted in a multi-app layout, introduced in iOS 9, see also the
         documentation of AVCaptureSessionInterruptionReason. Add observers to
         handle these session interruptions and show a preview is paused
         message. See the documentation of
         AVCaptureSessionWasInterruptedNotification for other interruption
         reasons.
         */
        notificationCenter.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        notificationCenter.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)

        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }

    @objc func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }

    @objc func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }

        print("Capture session runtime error: \(error)")

        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        //self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            //resumeButton.isHidden = false
        }
    }

    @objc func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios we want to enable the user to resume the session
         running. For example, if music playback is initiated via control center
         while using App, then the user can let App resume the session
         running, which will stop music playback. Note that stopping music
         playback in control center will not automatically resume the session
         running. Also note that it is not always possible to resume, see
         `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")

            var showResumeButton = false

            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                showResumeButton = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                //cameraUnavailableLabel.alpha = 0
                //cameraUnavailableLabel.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    //self.cameraUnavailableLabel.alpha = 1
                }
            }

            if showResumeButton {
                // Simply fade-in a button to enable the user to try to resume the session running.
                //resumeButton.alpha = 0
                //resumeButton.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    //self.resumeButton.alpha = 1
                }
            }
        }
    }

    @objc func sessionInterruptionEnded(notification: NSNotification) {
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        var uniqueDevicePositions: [AVCaptureDevice.Position] = []

        for device in devices {
            if !uniqueDevicePositions.contains(device.position) {
                uniqueDevicePositions.append(device.position)
            }
        }

        return uniqueDevicePositions.count
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToUIApplicationOpenExternalURLOptionsKeyDictionary(_ input: [String: Any]) -> [UIApplication.OpenExternalURLOptionsKey: Any] {
    return Dictionary(uniqueKeysWithValues: input.map { key, value in (UIApplication.OpenExternalURLOptionsKey(rawValue: key), value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromUIBackgroundTaskIdentifier(_ input: UIBackgroundTaskIdentifier) -> Int {
    return input.rawValue
}
