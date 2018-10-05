//
//  PhotoCaptureProcessor.swift
//  CustomCamera
//
//  Created by Nicolás Miari on 2018/09/26.
//  Copyright © 2018 Nicolás Miari. All rights reserved.
//

import AVFoundation
import Photos

/**
 Based on similarly named class from Apple's sample code (simplified by removing
 support for viewo and live photo).
 */
class PhotoCaptureProcessor: NSObject {

    var deviceOrientation: UIDeviceOrientation = .portrait

    private(set) var requestedPhotoSettings: AVCapturePhotoSettings

    private let willCapturePhotoAnimation: () -> Void

    private let completionHandler: (PhotoCaptureProcessor) -> Void

    private var photoData: Data?

    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
    }

    private func didFinish() {
        completionHandler(self)
    }
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            return
        }
        self.photoData = photo.fileDataRepresentation()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            return didFinish()
        }
        guard let photoData = photoData else {
            print("No photo data resource")
            return didFinish()
        }

        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
                    creationRequest.addResource(with: .photo, data: photoData, options: options)

                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurered while saving photo to photo library: \(error)")
                    }

                    self.didFinish()
                }
                )
            } else {
                self.didFinish()
            }
        }
    }
}
