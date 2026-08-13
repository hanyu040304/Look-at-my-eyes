# Look At My Eyes

Look At My Eyes 是一个原生 iOS 合影相机 App：先从短连拍里寻找所有人都睁眼的真实照片；如果没有完美帧，再用本地 Vision/Core Image 只修复闭眼者的眼部区域。

Look At My Eyes is a native iOS group-photo camera app. It first searches a short burst for a real frame where everyone has open eyes; if no perfect frame exists, it locally repairs only the closed-eye regions with Vision and Core Image.

## 简短介绍 / Short Description

```text
原生 iOS 合影相机：优先选择全员睁眼的连拍原图；必要时只局部修复闭眼者眼部区域。
```

```text
A native iOS group-photo camera that selects the best open-eye burst frame first, then locally repairs only closed-eye regions when needed.
```

## 项目目标 / Purpose

合影最常见的问题往往很小：大家都挺好，只有一个人闭眼。很多自动修复会替换太大范围的人脸，结果容易出现皮肤像磨皮、眼镜错位、脸型变化、表情不自然等问题。

The common group-photo failure is usually tiny: everyone looks good except one person blinked. Many automatic fixes replace too much of the face, which can create smoothed skin, misaligned glasses, changed facial geometry, or unnatural expressions.

这个项目采用更保守的流程：

- 先找真实存在的全员睁眼帧。
- 如果找到了，直接使用这张照片，不做修复。
- 如果没找到，再选择睁眼人数最多、素材质量最好的帧作为基底。
- 只修复基底图里仍然闭眼的人。
- 只融合眼睛附近的小区域，不替换整张脸。
- 尽量全部在设备本地完成，不依赖云端服务。

The app takes a conservative approach:

- Prefer a real frame where every tracked person has open eyes.
- If that frame exists, use it directly without patching.
- If not, choose the best base frame with the most open-eyed people.
- Repair only the people who blinked in that base frame.
- Blend only small eye regions instead of replacing whole faces.
- Keep processing local on device where possible.

## 功能 / Features

- 原生 SwiftUI 相机界面。
- Native SwiftUI camera UI.
- 连续运行的 `AVCaptureSession` 相机预览。
- Continuous `AVCaptureSession` preview.
- 类似 iPhone Camera 的方向处理：预览流不重启，只旋转 overlay controls，拍照输出进入结果页前做 upright 像素归一化。
- iPhone Camera style orientation handling: the preview keeps running, only overlay controls rotate, and captured output is normalized to upright pixels before result preview.
- 支持前置和后置摄像头。
- Front and back camera support.
- 后置镜头倍率选择，横竖屏切换时按钮位置保持稳定。
- Stable back-camera zoom selector.
- 拍照规格选择：2MP、24MP、设备支持时可用 48MP。
- Photo resolution selector: 2MP, 24MP, and 48MP when supported by the device/camera format.
- 支持 iPhone Camera Control / 物理相机键 / 音量键拍照事件，在 `event.phase == .ended` 时触发拍摄。
- Hardware shutter support for iPhone Camera Control / physical camera key / volume-key capture events, triggering capture on `event.phase == .ended`.
- 拍摄或处理中会忽略重复触发。
- Duplicate capture events are ignored while capturing or processing.
- 短连拍 + 高清 still photo。
- Short burst capture plus a high-resolution still photo.
- 使用 Vision 在本地做人脸和 landmark 检测。
- Local face and landmark detection with Vision.
- 使用 Eye Aspect Ratio 评估睁眼程度。
- Eye-open scoring using Eye Aspect Ratio.
- 优先选择全员睁眼帧作为基底图；没有全员睁眼帧时，再选择睁眼人数最多、质量最高的帧。
- Base-frame selection prefers a frame where all tracked people are open-eyed; otherwise it falls back to the highest-quality frame with the most open-eyed people.
- 眼部局部融合：左右眼独立处理、landmark 对齐、相似变换、轻量局部颜色匹配、小范围 feather mask。
- Eye-only blending: independent left/right eye processing, landmark alignment, similarity transform, lightweight local color matching, and small feathered masks.
- 不对 source 图像做 blur，不做美颜磨皮。
- No source-image blur and no beauty smoothing.
- 结果页支持原图 / 优化后切换、识别人数、修复数量、处理耗时、连拍帧数量展示。
- Result preview supports original / optimized comparison, detected person count, fixed count, processing time, and burst frame count.
- 可保存优化图，或同时保存原图和优化图。
- Save optimized result or both original and optimized images.
- 保存到相册时尽量写入真实捕获 metadata 和相机/镜头信息。
- Photo-library export includes real capture metadata and camera/lens details when available.
- 连拍帧 gallery 可用于查看素材帧和调试。
- Burst frame gallery is available for inspecting source frames and debugging.

## 下载源码 / Download Source

你可以用 Git 克隆仓库：

```sh
git clone https://github.com/hanyu040304/Look-at-my-eyes.git
cd Look-at-my-eyes
```

You can clone the repository with Git:

```sh
git clone https://github.com/hanyu040304/Look-at-my-eyes.git
cd Look-at-my-eyes
```

也可以在 GitHub 页面点击：

```text
Code -> Download ZIP
```

下载 ZIP 后解压，进入解压出来的文件夹即可。

Or click this on GitHub:

```text
Code -> Download ZIP
```

After downloading, unzip it and open the extracted folder.

## 环境要求 / Requirements

- macOS。
- Xcode 17 或更新版本。
- 与本机 Xcode SDK 匹配的 iPhone/iOS target。
- 真机运行需要 Apple Developer 签名。
- 推荐使用真实 iPhone 测试，因为核心功能依赖相机，模拟器无法完整测试真实拍照流程。

- macOS.
- Xcode 17 or newer.
- iPhone/iOS target support matching your installed Xcode SDK.
- Apple Developer signing for physical-device runs.
- A real iPhone is strongly recommended because the core feature depends on real camera capture.

当前项目的 `IPHONEOS_DEPLOYMENT_TARGET` 是 `26.5`，这是开发机上的 Xcode/iPhone SDK 版本。如果你的 Xcode 版本不同，可以在 Xcode project settings 里调整 deployment target。

The current `IPHONEOS_DEPLOYMENT_TARGET` is `26.5`, matching the local SDK used during development. If your Xcode version differs, adjust the deployment target in the project settings.

## 打开工程 / Open The Project

在 Finder 中双击：

```text
Grouper.xcodeproj
```

或者在终端执行：

```sh
open Grouper.xcodeproj
```

Open this file in Finder:

```text
Grouper.xcodeproj
```

Or run:

```sh
open Grouper.xcodeproj
```

打开后确认：

- Scheme 选择 `Grouper`。
- 如果要跑真机，左上角设备选择你的 iPhone。
- 如果只是验证能不能编译，可以先选择任意 iOS Simulator。

After opening the project:

- Select the `Grouper` scheme.
- Choose your connected iPhone if you want to run on device.
- Choose an iOS Simulator if you only want to verify compilation.

## 模拟器编译 / Build For Simulator

模拟器可以用于检查项目是否能编译，但不能完整测试真实相机拍照流程。

The simulator is useful for verifying compilation, but it cannot fully test the real camera flow.

```sh
xcodebuild \
  -project Grouper.xcodeproj \
  -scheme Grouper \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

如果这个命令通过，说明源码和 Xcode 工程基本正常。

If this command passes, the source code and Xcode project are basically healthy.

## 真机运行 / Run On iPhone

1. 用 Xcode 打开 `Grouper.xcodeproj`。
2. 选择 `Grouper` scheme。
3. 连接 iPhone，并在设备列表中选择它。
4. 打开 target `Grouper` 的 `Signing & Capabilities`。
5. 在 `Team` 里选择你的 Apple Developer Team。
6. 如果 Bundle Identifier 和你的账号冲突，把 `com.hanyu.grouper` 改成你自己的唯一 bundle id，例如 `com.yourname.lookatmyeyes`。
7. 点击 Run。
8. 第一次运行时，在 iPhone 上信任开发者证书。
9. 打开 App 后允许相机和相册写入权限。

1. Open `Grouper.xcodeproj` in Xcode.
2. Select the `Grouper` scheme.
3. Connect your iPhone and select it as the run destination.
4. Open `Signing & Capabilities` for the `Grouper` target.
5. Choose your Apple Developer Team.
6. If the Bundle Identifier conflicts with your account, change `com.hanyu.grouper` to your own unique bundle id, such as `com.yourname.lookatmyeyes`.
7. Press Run.
8. Trust the developer certificate on your iPhone if prompted.
9. Allow camera and photo-library permissions in the app.

命令行真机构建：

Command-line device build:

```sh
xcodebuild \
  -project Grouper.xcodeproj \
  -scheme Grouper \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

## 从 Releases 下载 / Download From Releases

GitHub Releases 页面：

GitHub Releases page:

```text
https://github.com/hanyu040304/Look-at-my-eyes/releases
```

如果 Release 中提供了源码压缩包：

1. 打开 Releases 页面。
2. 选择最新版本。
3. 下载 `Source code (zip)` 或 `Source code (tar.gz)`。
4. 解压后打开 `Grouper.xcodeproj`。
5. 按上面的“真机运行”步骤配置签名并运行。

If a release provides source archives:

1. Open the Releases page.
2. Choose the latest version.
3. Download `Source code (zip)` or `Source code (tar.gz)`.
4. Unzip it and open `Grouper.xcodeproj`.
5. Follow the device-running steps above to configure signing and run.

如果 Release 中提供了 `.ipa`：

1. 这个 IPA 仍然必须经过有效签名。
2. 普通未越狱 iPhone 不能安装完全未签名的 IPA。
3. Development / Ad Hoc IPA 通常只支持已登记或已授权的设备。
4. 如果你的设备不在签名描述文件里，下载 IPA 也无法直接安装。

If a release provides an `.ipa`:

1. The IPA must still be validly signed.
2. Normal non-jailbroken iPhones cannot install fully unsigned IPAs.
3. Development / Ad Hoc IPAs usually only work on registered or authorized devices.
4. If your device is not included in the provisioning profile, the downloaded IPA will not install.

## 生成本地 IPA / Build A Local IPA

先 archive：

First create an archive:

```sh
xcodebuild \
  -project Grouper.xcodeproj \
  -scheme Grouper \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Grouper.xcarchive \
  -allowProvisioningUpdates \
  archive
```

然后准备一个 `build/ExportOptions.plist`。Development 签名示例：

Then prepare `build/ExportOptions.plist`. Example for development signing:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>compileBitcode</key>
  <false/>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
```

导出 IPA：

Export the IPA:

```sh
xcodebuild \
  -exportArchive \
  -archivePath build/Grouper.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates
```

导出的文件通常在：

The exported file is usually here:

```text
build/export/Grouper.ipa
```

`build/` 已被 `.gitignore` 忽略，不会进入仓库。

`build/` is ignored by Git and should not be committed.

## 分享测试包 / Sharing Test Builds

普通 iPhone 不能安装未签名 IPA。如果要分享给别人测试：

- 推荐：TestFlight，适合较多人测试。
- 小范围私测：Ad Hoc，需要提前收集测试设备 UDID 并加入 Apple Developer 账号。
- 自己测试：Xcode 直接安装到自己的 iPhone。

Normal iPhones cannot install unsigned IPAs. To share builds:

- Recommended: TestFlight for broader testing.
- Small private testing: Ad Hoc, requiring tester UDIDs registered in your Apple Developer account.
- Personal testing: direct Xcode install to your own iPhone.

## 常见问题 / Troubleshooting

### Xcode 提示没有 provisioning profile

你需要在 `Signing & Capabilities` 中选择自己的 Team，或者把 Bundle Identifier 改成你账号下唯一的 id。

If Xcode says no provisioning profile is available, choose your own Team in `Signing & Capabilities`, or change the Bundle Identifier to a unique id under your account.

### 真机无法安装 IPA

通常是签名不匹配。Development / Ad Hoc IPA 只能安装到签名描述文件允许的设备。

This is usually a signing mismatch. Development / Ad Hoc IPAs can only be installed on devices allowed by the provisioning profile.

### 模拟器没有真实相机

这是正常现象。相机 App 的核心流程需要真机测试。

This is expected. The core camera flow needs a real device.

### interface orientations warning

当前项目优先在 iPhone 上跑通，iPad orientation 支持没有作为当前重点。如果你要完善 iPad 支持，需要调整 supported interface orientations 和相关布局策略。

The current project prioritizes iPhone behavior. iPad orientation support is not the current focus. To improve iPad support, update supported interface orientations and related layout behavior.

## 非目标 / Non-Goals

- 不是云端 AI 修图工具。
- Not a cloud AI photo editor.
- 不是美颜相机。
- Not a beauty camera.
- 不是完整的 Photoshop 式人脸合成工具。
- Not a full Photoshop-style face compositor.
- 不是 App Store 分发模板。
- Not an App Store distribution template.
- 不会把大型本地 SDK、缓存、构建产物放进仓库。
- Not intended to ship large local SDKs, caches, or generated build output in the repository.

## 技术栈 / Tech Stack

- Swift
- SwiftUI
- AVFoundation
- Vision
- Core Image
- Photos
- ImageIO

当前项目是原生 iOS Xcode 工程。早期 Flutter 原型和本地 Flutter SDK/cache 已在开源前移出仓库。

The current project is a native iOS Xcode project. Older Flutter prototype files and local Flutter SDK/cache folders were moved out before publishing.

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

1. 开始短连拍。
2. 捕获采样预览帧和高清 still photo。
3. 归一化拍照方向，确保像素方向 upright。
4. 本地检测人脸和 landmark。
5. 在连拍帧之间跟踪人物。
6. 选择最佳基底图：如果有全员睁眼帧，直接选它；否则选择睁眼人数最多、质量最高的帧。
7. 对基底图中仍然闭眼的人，查找最佳睁眼素材帧。
8. 检查 eye landmarks、睁眼程度、脸框相似度、眼距和眼轴角度。
9. 只融合小范围眼部区域。
10. 渲染结果预览。
11. 保存图片和可用 metadata。

1. Start a short burst.
2. Capture sampled preview frames and a high-resolution still.
3. Normalize capture orientation so image pixels are upright.
4. Detect faces and landmarks locally.
5. Track faces across burst frames.
6. Select the best base frame: use a fully open-eye frame if possible; otherwise choose the highest-quality frame with the most open-eyed people.
7. For each still-closed person in the base frame, find the best open-eye material frame.
8. Check eye landmarks, eye openness, face similarity, eye distance, and eye angle.
9. Blend only small eye regions.
10. Render result preview.
11. Save images with available metadata.

## 许可证 / License

MIT. See [LICENSE](LICENSE).
