# Look At My Eyes

> 中文：一个原生 iOS 合影相机实验项目。它通过短连拍、本地人脸/眼部 landmark 检测和保守的眼部局部融合，优先选择所有人都睁眼的真实照片；只有确实有人闭眼时，才只修复眼睛附近的小区域。
>
> English: A native iOS group-photo camera experiment. It captures a short burst, detects faces and eye landmarks locally, prefers a real frame where everyone has open eyes, and only blends small eye regions when a blink repair is necessary.

简短介绍 / Short Description:

```text
Look At My Eyes is a native iOS camera app that fixes blinked group photos locally by selecting the best burst frame first, then repairing only closed-eye regions when needed.
```

```text
Look At My Eyes 是一个原生 iOS 合影相机 App：先从连拍里选择所有人都睁眼的真实照片；如果没有，再用本地 Vision/Core Image 只修复闭眼者的眼部区域。
```

## 项目目的 / Purpose

中文：

合影最常见的问题不是构图，也不是画质，而是“大家都挺好，只有一个人闭眼”。很多自动修复会替换太大范围的人脸，导致皮肤像磨皮、眼镜错位、脸型变化或者表情不自然。

这个项目的目标是做一个更保守的闭眼修复流程：

- 先在连拍中寻找所有人都睁眼的真实照片。
- 如果找到了，直接使用这张照片，不做 P 图修复。
- 如果没有全员睁眼帧，再选择睁眼人数最多、质量最好的照片作为基底。
- 只修复基底图里闭眼的人。
- 只融合眼睛附近的小区域，不替换整张脸。
- 全部处理尽量在本机完成，不依赖云端服务。

English:

The most common failure in group photos is simple: everyone looks good except one person blinked. Many automatic fixes replace too much of the face, which can create fake-looking skin, misaligned glasses, changed facial geometry, or unnatural expressions.

This project takes a conservative approach:

- First look for a real burst frame where every tracked person has open eyes.
- If such a frame exists, use it directly without patching.
- If not, choose the best base frame with the most open-eyed people.
- Repair only the people who blinked in that base frame.
- Blend only small eye regions instead of replacing whole faces.
- Keep processing local on device where possible.

## 功能 / Features

中文：

- 原生 SwiftUI 相机界面。
- 连续运行的 `AVCaptureSession` 预览。
- 类似 iPhone Camera 的方向处理：
  - 预览流保持连续；
  - 设备旋转时只旋转 overlay controls；
  - 拍照输出在进入结果页前做 upright 像素归一化。
- 支持前置和后置摄像头。
- 后置镜头倍率选择，按钮位置在横竖屏切换时保持稳定。
- 拍照规格选择：
  - 2MP
  - 24MP
  - 设备支持时可用 48MP
- 支持物理拍照键：
  - iPhone Camera Control / 物理相机键；
  - 音量键拍照事件；
  - 在 `event.phase == .ended` 时触发拍摄；
  - 拍摄或处理中会忽略重复触发。
- 短连拍 + 高清 still photo。
- 使用 Vision 在本地做人脸和 landmark 检测。
- 使用 Eye Aspect Ratio 评估睁眼程度。
- 基底图选择：
  - 优先找所有已跟踪人物都睁眼的帧；
  - 找不到时选择睁眼人数最多、质量最高的帧；
  - 再对剩余闭眼人物做局部修复。
- 眼部局部融合：
  - 左右眼独立处理；
  - 使用 landmark 对齐；
  - 使用相似变换做平移、缩放和旋转；
  - 轻量局部颜色匹配；
  - 小范围 feather mask；
  - 不对 source 图像做 blur，不做美颜磨皮。
- 结果预览：
  - 原图 / 优化后切换；
  - 识别人数；
  - 修复闭眼数量；
  - 处理耗时；
  - 连拍帧数量。
- 可保存优化结果，或同时保存原图和优化图。
- 保存到相册时尽量写入真实捕获元数据和相机/镜头信息。
- 连拍帧 gallery，用于检查素材帧和调试。

English:

- Native SwiftUI camera UI.
- Continuous `AVCaptureSession` preview.
- iPhone Camera style orientation handling:
  - preview keeps running continuously;
  - only overlay controls rotate when the device rotates;
  - captured output is normalized to upright pixels before result preview.
- Front and back camera support.
- Stable back-camera zoom selector.
- Photo resolution selector:
  - 2MP
  - 24MP
  - 48MP when supported by the device/camera format
- Hardware shutter support:
  - iPhone Camera Control / physical camera key;
  - volume-key capture events;
  - capture starts on `event.phase == .ended`;
  - duplicate events are ignored while capturing or processing.
- Short burst capture plus a high-resolution still photo.
- Local face and landmark detection with Vision.
- Eye-open scoring using Eye Aspect Ratio.
- Base-frame selection:
  - prefer a frame where all tracked people are open-eyed;
  - otherwise choose the highest-quality frame with the most open-eyed people;
  - then repair only the remaining closed-eye subjects.
- Eye-only blending:
  - independent left/right eye processing;
  - landmark alignment;
  - similarity transform for translation, scale, and rotation;
  - lightweight local color matching;
  - small feathered masks;
  - no source-image blur or beauty smoothing.
- Result preview:
  - original / optimized comparison;
  - detected person count;
  - fixed closed-eye count;
  - processing time;
  - burst frame count.
- Save optimized result or both original and optimized images.
- Photo-library export with real capture metadata and camera/lens details when available.
- Burst frame gallery for inspecting source frames and debugging.

## 非目标 / Non-Goals

中文：

- 不是云端 AI 修图工具。
- 不是美颜相机。
- 不是完整的 Photoshop 式人脸合成工具。
- 不是 App Store 分发模板。
- 不会把大型本地 SDK、缓存、构建产物放进仓库。

English:

- Not a cloud AI photo editor.
- Not a beauty camera.
- Not a full Photoshop-style face compositor.
- Not an App Store distribution template.
- Not intended to ship large local SDKs, caches, or generated build output in the repository.

## 技术栈 / Tech Stack

- Swift
- SwiftUI
- AVFoundation
- Vision
- Core Image
- Photos
- ImageIO

中文：

当前项目是原生 iOS Xcode 工程。早期 Flutter 原型和本地 Flutter SDK/cache 已在开源前移出仓库。

English:

The current project is a native iOS Xcode project. Older Flutter prototype files and local Flutter SDK/cache folders were moved out before publishing.

## 环境要求 / Requirements

中文：

- macOS。
- Xcode 17 或更新版本。
- 与本机 Xcode SDK 匹配的 iPhone/iOS target。
- 真机运行需要 Apple Developer 签名。
- 推荐使用真实 iPhone 测试，因为核心功能依赖相机。

当前项目的 `IPHONEOS_DEPLOYMENT_TARGET` 是 `26.5`，这是开发机上的 Xcode/iPhone SDK 版本。如果你使用其他 Xcode 版本，可以在 Xcode project settings 里调整 deployment target。

English:

- macOS.
- Xcode 17 or newer.
- iPhone/iOS target support matching your installed Xcode SDK.
- Apple Developer signing for physical-device runs.
- A real iPhone is strongly recommended because the main feature depends on camera capture.

The current `IPHONEOS_DEPLOYMENT_TARGET` is `26.5`, matching the local SDK used during development. If your Xcode version differs, adjust the deployment target in the project settings.

## 构建 / Build

打开工程 / Open the project:

```sh
open Grouper.xcodeproj
```

模拟器构建 / Build for simulator:

```sh
xcodebuild \
  -project Grouper.xcodeproj \
  -scheme Grouper \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

真机构建 / Build for physical iPhone:

```sh
xcodebuild \
  -project Grouper.xcodeproj \
  -scheme Grouper \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

## 在 iPhone 上运行 / Run On iPhone

中文：

1. 用 Xcode 打开 `Grouper.xcodeproj`。
2. 选择 `Grouper` scheme。
3. 选择连接的 iPhone。
4. 在 Signing & Capabilities 中选择你的 Apple Developer Team。
5. 点击 Run。
6. 按提示允许相机和相册权限。

English:

1. Open `Grouper.xcodeproj` in Xcode.
2. Select the `Grouper` scheme.
3. Select your connected iPhone.
4. In Signing & Capabilities, choose your Apple Developer Team.
5. Press Run.
6. Allow camera and photo-library permissions when prompted.

## 测试包分享 / Sharing Test Builds

中文：

普通未越狱 iPhone 不能安装完全未签名的 IPA。如果要分享给别人测试，可以使用：

- TestFlight：适合较多人测试。
- Ad Hoc / registered devices：适合少量私测，需要提前登记测试设备 UDID。
- Xcode 直接安装：适合自己的设备。

生成的 archive 和 IPA 应放在 `build/`，该目录已被 Git 忽略。

English:

Normal non-jailbroken iPhones cannot install fully unsigned IPAs. To share builds with testers, use:

- TestFlight for broader testing.
- Ad Hoc / registered devices for small private testing.
- Direct Xcode install for your own device.

Generated archives and IPA files belong in `build/`, which is ignored by Git.

## 仓库清理 / Repository Hygiene

中文：

仓库会忽略：

- `build/`
- DerivedData
- Xcode user state
- `.DS_Store`
- 本地 Flutter SDK/cache
- Swift 和包管理缓存
- 生成的 IPA/archive 文件

开源前，大型本地文件已经移动到项目旁边的本地归档目录，而不是直接删除。它们不是当前原生 iOS 项目运行所必需的内容。

English:

The repository intentionally excludes:

- `build/`
- DerivedData
- Xcode user state
- `.DS_Store`
- local Flutter SDK/cache folders
- Swift and package-manager caches
- generated IPA/archive files

Large local files useful during development were moved to a sibling archive directory before publishing. They are not required for the current native iOS project.

## 项目结构 / Project Structure

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

## 处理流程 / Processing Pipeline

中文：

1. 开始短连拍。
2. 捕获采样预览帧和高清 still photo。
3. 归一化拍照方向，确保像素方向 upright。
4. 本地检测人脸和 landmark。
5. 在连拍帧之间跟踪人物。
6. 选择最佳基底图：
   - 如果有全员睁眼帧，直接选它；
   - 否则选择睁眼人数最多、质量最高的帧。
7. 对基底图中仍然闭眼的人：
   - 查找最佳睁眼素材帧；
   - 要求眼部 landmark 可用；
   - 检查睁眼程度、landmark 置信度、脸框相似度、眼距和眼轴角度；
   - 只融合小范围眼部区域。
8. 渲染结果预览。
9. 保存图片和可用 metadata。

English:

1. Start a short burst.
2. Capture sampled preview frames and a high-resolution still.
3. Normalize capture orientation so image pixels are upright.
4. Detect faces and landmarks locally.
5. Track faces across burst frames.
6. Select the best base frame:
   - if all tracked people are open-eyed in one frame, use it directly;
   - otherwise choose the highest-quality frame with the most open-eyed people.
7. For each person still closed-eyed in the base:
   - find the best open-eye material frame;
   - require usable eye landmarks;
   - check eye openness, landmark confidence, face similarity, eye distance, and eye angle;
   - blend only small eye regions.
8. Render result preview.
9. Save images with available metadata.

## License

MIT. See [LICENSE](LICENSE).
