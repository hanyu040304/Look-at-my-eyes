# Look At My Eyes

Look At My Eyes is an experimental native iOS camera app for group photos. It captures a short burst, detects faces locally, chooses the best frame where people have open eyes, and only blends small eye regions when a repair is actually needed.

The goal is not to make a beauty filter. The goal is to reduce the most common group-photo failure mode: one person blinked.

## Why This Exists

Group photos often fail for a tiny reason: everyone looks good except one person blinked. Most automatic fixes replace too much of the face, which can look fake, smooth skin unnaturally, shift glasses, or change someone's expression.

This project explores a more conservative approach:

- Prefer a real burst frame where everyone already has open eyes.
- If such a frame exists, use it directly and do not patch.
- If no perfect frame exists, choose the frame with the most open eyes as the base.
- Repair only the people who blinked.
- Repair only the eye area, not the whole face.
- Keep all processing local on device with Apple's camera, Vision, and Core Image frameworks.

## Current Features

- Native SwiftUI camera interface.
- Continuous `AVCaptureSession` preview.
- iPhone Camera style orientation handling:
  - camera preview stays continuous;
  - overlay controls rotate smoothly;
  - captured image output is normalized to upright pixels before preview.
- Front and back camera support.
- Back-camera zoom selector with stable on-screen placement.
- Photo resolution selector:
  - 2MP
  - 24MP
  - 48MP when supported by the device/camera format
- Hardware shutter support:
  - iPhone Camera Control / physical camera key
  - volume key capture event
  - triggers capture on `event.phase == .ended`
  - ignores repeated events while capturing or processing
- Short burst capture plus a high-resolution still photo.
- Local face and landmark detection using Vision.
- Eye-open scoring using eye aspect ratio.
- Base-frame selection:
  - first tries to find a burst frame where all tracked people are open-eyed;
  - falls back to the frame with the most open-eyed people;
  - then repairs only remaining closed-eye subjects.
- Eye-only repair:
  - independent left/right eye blending;
  - landmark-aligned similarity transform;
  - lightweight local color matching;
  - small feathered masks;
  - no source-image blur or beauty smoothing.
- Result preview:
  - original vs optimized comparison;
  - person count;
  - fixed closed-eye count;
  - processing time;
  - burst frame count.
- Save optimized result or save both original and optimized images.
- Photo-library export with capture metadata and camera/lens details when available from the real capture device.
- Burst frame gallery for debugging and reviewing source frames.

## What This Is Not

- Not a cloud AI photo editor.
- Not a face beautification app.
- Not a full Photoshop-style compositor.
- Not an App Store distribution template.
- Not intended to ship large local SDKs, caches, or generated build output in the repository.

## Tech Stack

- Swift
- SwiftUI
- AVFoundation
- Vision
- Core Image
- Photos
- ImageIO

The current app is a native iOS Xcode project. Older Flutter prototype files and local Flutter SDK/cache folders were moved out of the repository before publishing.

## Requirements

- macOS with Xcode 17 or newer.
- iPhone target support matching the installed Xcode SDK.
- Apple Developer signing for running on a physical device.
- A real iPhone is strongly recommended because the main feature depends on camera capture.

The project currently targets iOS `26.5` because it was built on the local Xcode/iPhone SDK used during development. If you are using a different Xcode version, adjust `IPHONEOS_DEPLOYMENT_TARGET` in the project settings as needed.

## Build

Open the project:

```sh
open Grouper.xcodeproj
```

Or build from the command line for simulator:

```sh
xcodebuild \
  -project Grouper.xcodeproj \
  -scheme Grouper \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For a physical iPhone, use Xcode automatic signing with your own Apple Developer team:

```sh
xcodebuild \
  -project Grouper.xcodeproj \
  -scheme Grouper \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

## Run On iPhone

1. Open `Grouper.xcodeproj` in Xcode.
2. Select the `Grouper` scheme.
3. Select your connected iPhone.
4. In Signing & Capabilities, choose your Apple Developer Team.
5. Press Run.
6. Allow camera and photo-library permissions when prompted.

## Sharing Test Builds

iOS does not allow unsigned IPA installation on normal non-jailbroken devices. To share builds with testers, use one of:

- TestFlight for broader testing.
- Ad Hoc / registered devices for small private testing.
- Direct Xcode install for your own device.

Generated archives and IPA files belong in `build/`, which is intentionally ignored by Git.

## Repository Hygiene

The repository intentionally excludes:

- `build/`
- DerivedData
- Xcode user state
- `.DS_Store`
- local Flutter SDK/cache folders
- Swift and package-manager caches
- generated IPA/archive files

Large local files that were useful during development were moved to a sibling archive directory instead of being deleted. They are not required for the current native iOS project.

## Project Structure

```text
Grouper/
  Camera/
    CameraViewModel.swift
    GroupCameraView.swift
    CameraPreviewView.swift
    CaptureButton.swift
    ZoomSelectorView.swift
    ResultPreviewView.swift
    BurstFramesGalleryView.swift
  GroupPhotoProcessor.swift
  GrouperApp.swift
  ContentView.swift
  Assets.xcassets/
Grouper.xcodeproj/
GrouperTests/
GrouperUITests/
```

## Processing Pipeline

1. Start a short burst.
2. Capture sampled preview frames and a high-resolution still.
3. Normalize capture orientation so image pixels are upright.
4. Detect faces and landmarks locally.
5. Track faces across burst frames.
6. Select the best base frame:
   - all tracked people open-eyed if possible;
   - otherwise the highest-scoring partial-open frame.
7. For each person still closed-eyed in the base:
   - find the best open-eye material frame;
   - require usable eye landmarks;
   - check eye openness, landmark confidence, face similarity, eye distance, and eye angle;
   - blend only small eye regions.
8. Render result preview.
9. Save images with available metadata.

## License

MIT. See [LICENSE](LICENSE).
