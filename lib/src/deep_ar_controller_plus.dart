import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import 'deep_ar_platform_handler.dart';
import 'platform_strings.dart';
import 'resolution_preset.dart';
import 'utils.dart';

/// Controls all interaction with DeepAR Sdk.
class DeepArControllerPlus {
  late final DeepArPlatformHandler _deepArPlatformHandler;
  late final Resolution _resolution;

  int? _textureId;
  Size? _imageSize;
  double? _aspectRatio;
  bool _hasPermission = false;
  String? _iosLicenseKey;
  bool _isRecording = false;

  CameraDirection _cameraDirection = CameraDirection.front;
  bool _flashState = false;

  DeepArControllerPlus() {
    _deepArPlatformHandler = DeepArPlatformHandler();
  }

  ///Return true if the camera preview is initialized
  ///
  ///For [iOS], please call the function after [DeepArPreviewPlus] widget has been built.
  bool get isInitialized => _textureId != null;

  ///If the user has allowed required camera permissions
  bool get hasPermission => _hasPermission;

  ///Aspect ratio of the preview image
  ///
  ///For [iOS], please call the function after [DeepArPreviewPlus] widget has been built.
  double get aspectRatio => _aspectRatio ?? 1.0;

  ///Return true if the recording is in progress.
  bool get isRecording => _isRecording;

  ///Get current flash state as [FlashState.on] or [FlashState.off]
  bool get flashState => _flashState;

  ///Size of the preview image
  ///
  ///For [iOS], please call the function after [DeepArPreviewPlus] widget has been built.
  Size get imageDimensions {
    assert(isInitialized, "DeepArController isn't initialized yet");
    return _imageSize!;
  }

  ///Get current  camera direction as [CameraDirection.front] or [CameraDirection.rear]
  CameraDirection get cameraDirection => _cameraDirection;

  ///Initializes the DeepAR SDK with license keys and asks for required camera and microphone permissions.
  ///Returns false if fails to initialize.
  ///
  ///[androidLicenseKey] and [iosLicenseKey] both cannot be null together.
  ///
  ///Recommended resolution: [Resolution.medium] for optimum quality without performance tradeoffs
  Future<bool> initialize({
    required String? androidLicenseKey,
    required String? iosLicenseKey,
    Resolution resolution = Resolution.medium,
  }) async {
    assert(androidLicenseKey != null || iosLicenseKey != null,
        "Both android and iOS license keys cannot be null");

    _iosLicenseKey = iosLicenseKey;
    _resolution = resolution;
    _hasPermission = await _askMediaPermission();

    if (!_hasPermission) return false;

    if (Platform.isAndroid) {
      assert(androidLicenseKey != null, "androidLicenseKey missing");
      String? dimensions = await _deepArPlatformHandler.initialize(
          androidLicenseKey!, resolution);
      if (dimensions != null) {
        _imageSize = sizeFromEncodedString(dimensions);
        _aspectRatio = _imageSize!.width / _imageSize!.height;
        _textureId = await _deepArPlatformHandler.startCameraAndroid();
        return true;
      }
    } else if (Platform.isIOS) {
      assert(iosLicenseKey != null, "iosLicenseKey missing");
      _imageSize = iOSImageSizeFromResolution(resolution);
      _aspectRatio = _imageSize!.width / _imageSize!.height;
      return true;
    } else {
      throw ("Platform not supported");
    }
    return false;
  }

  ///Builds and returns the DeepAR Camera Preview.
  ///
  ///[oniOSViewCreated] callback to update [imageDimensions] and [aspectRatio] after iOS
  ///widget is built
  ///
  ///Not recommended to use directly. Please use the wrapper [DeepArPreviewPlus] instead.
  ///
  ///Android layer uses FlutterTexture while iOS uses NativeViews.
  ///See: https://api.flutter.dev/flutter/widgets/Texture-class.html
  ///https://docs.flutter.dev/development/platform-integration/ios/platform-views
  Widget buildPreview({Function? oniOSViewCreated}) {
    if (Platform.isAndroid) {
      return Texture(textureId: _textureId!);
    } else if (Platform.isIOS) {
      return UiKitView(
          viewType: "deep_ar_view",
          layoutDirection: TextDirection.ltr,
          creationParams: <String, dynamic>{
            PlatformStrings.licenseKey: _iosLicenseKey,
            PlatformStrings.resolution: _resolution.stringValue
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: ((id) {
            _textureId = id;
            _deepArPlatformHandler
                .getResolutionDimensions(_textureId!)
                .then((value) {
              if (value != null) {
                _imageSize = sizeFromEncodedString(value);
                _aspectRatio = _imageSize!.width / _imageSize!.height;
              }
              _setNativeListenerIos();
              oniOSViewCreated?.call();
            });
          }));
    } else {
      throw ("Platform not supported.");
    }
  }

  ///Starts recording video
  Future<void> startVideoRecording() async {
    if (_isRecording) throw ("Recording already in progress");
    if (Platform.isAndroid) {
      _deepArPlatformHandler.startRecordingVideoAndroid();
      _isRecording = true;
    } else {
      _deepArPlatformHandler.startRecordingVideoIos(_textureId!);
      _isRecording = true;
    }
  }

  ///Stop recording video
  Future<File> stopVideoRecording() async {
    if (!_isRecording) {
      throw ("Invalid stopVideoRecording trigger. No recording was in progress");
    }
    final _file = await platformRun(
        androidFunction: _deepArPlatformHandler.stopRecordingVideoAndroid,
        iOSFunction: () =>
            _deepArPlatformHandler.stopRecordingVideoIos(_textureId!));
    _isRecording = false;
    if (_file == "ENDED_WITH_ERROR") throw ("Video capture failed");

    return File(_file!);
  }

  ///Takes picture of the current frame and returns a [File]
  Future<File> takeScreenshot() async {
    final _file = await platformRun(
        androidFunction: _deepArPlatformHandler.takeScreenShot,
        iOSFunction: () =>
            _deepArPlatformHandler.takeScreenShotIos(_textureId!));
    if (_file == "ENDED_WITH_ERROR") throw ("Screenshot capture failed");

    return File(_file!);
  }

  /// Helper function to handle file caching and path resolution
  /// Returns the file path for the effect, either from cache or local assets
  Future<String> _resolveEffectPath(String path, String effectType) async {
    try {
      final uri = Uri.parse(path);
      if (uri.isAbsolute) {
        // Check if it's a valid URL
        // Get file from cache or download it
        final file = await DefaultCacheManager().getSingleFile(path);
        return file.path;
      }
    } catch (e, s) {
      log('Network $effectType Error', error: e, stackTrace: s);
      // Not a URL, treat as asset path
    }
    return path;
  }

  ///Switch DeepAR with the passed [effect] path from assets, file paths or URL
  Future<String?> switchEffect(String effect) async {
    final effectPath = await _resolveEffectPath(effect, 'Effect');
    return platformRun(
        androidFunction: () =>
            _deepArPlatformHandler.switchEffectAndroid(effectPath),
        iOSFunction: () =>
            _deepArPlatformHandler.switchCameraIos(effectPath, _textureId!));
  }

  ///Load contents of a DeepAR Studio file as an effect/filter in the scene
  Future<void> switchEffectWithSlot(
      {required String slot,
      required String path,
      String? targetGameObject,
      int? face}) async {
    await platformRun(
        androidFunction: () =>
            _deepArPlatformHandler.switchEffectWithSlot(slot: slot, path: path),
        iOSFunction: () => _deepArPlatformHandler
            .switchEffectWithSlotIos(_textureId!, slot: slot, path: path));
  }

  ///Switch DeepAR with the passed [mask] path from assets, file path or URL
  Future<String?> switchFaceMask(String mask) async {
    final maskPath = await _resolveEffectPath(mask, 'Face Mask');
    return platformRun(
        androidFunction: () =>
            _deepArPlatformHandler.switchFaceMaskAndroid(maskPath),
        iOSFunction: () =>
            _deepArPlatformHandler.switchFaceMaskIos(maskPath, _textureId!));
  }

  ///Switch DeepAR with the passed [filter] path from assets, file path or URL
  Future<String?> switchFilter(String filter) async {
    final filterPath = await _resolveEffectPath(filter, 'Filter');
    return platformRun(
        androidFunction: () =>
            _deepArPlatformHandler.switchFilterAndroid(filterPath),
        iOSFunction: () =>
            _deepArPlatformHandler.switchFilterIos(filterPath, _textureId!));
  }

  ///Moves the selected game object from its current position in a tree and sets it as a direct child of a target game object.
  Future<void> moveGameObject(
      {required String selectedGameObjectName,
      required String targetGameObjectName}) async {
    await platformRun(
        androidFunction: () => _deepArPlatformHandler.moveGameObject(
            selectedGameObjectName, targetGameObjectName),
        iOSFunction: () => _deepArPlatformHandler.moveGameObjectIos(
            _textureId!, selectedGameObjectName, targetGameObjectName));
  }

  ///Changes a node or component newParameter.
  ///
  /// Only allowed datatype for newParameter are :
  /// String, Bool, Vector3, Vector4, Float
  Future<void> changeParameter({
    required String gameObject,
    required String component,
    required String parameter,
    dynamic newParameter,
  }) async {
    if (newParameter is String ||
        newParameter is bool ||
        newParameter is vector.Vector3 ||
        newParameter is vector.Vector4 ||
        newParameter is double) {
      Map<String, dynamic> arguments = {};
      arguments['gameObject'] = gameObject;
      arguments['component'] = component;
      arguments['parameter'] = parameter;

      if (newParameter is vector.Vector3) {
        arguments['x'] = newParameter.x;
        arguments['y'] = newParameter.y;
        arguments['z'] = newParameter.z;
      } else if (newParameter is vector.Vector4) {
        arguments['x'] = newParameter.x;
        arguments['y'] = newParameter.y;
        arguments['z'] = newParameter.z;
        arguments['w'] = newParameter.w;
      } else {
        arguments['newParameter'] = newParameter;
      }

      await platformRun(
          androidFunction: () =>
              _deepArPlatformHandler.changeParameter(arguments),
          iOSFunction: () => _deepArPlatformHandler.changeParameterIos(
              _textureId!, arguments));
    } else {
      debugPrint("Invalid datatype passed in newParameter");
      throw ("Invalid field newParameter. Please refer docs to pass correct value.");
    }
  }

  ///Flips Camera and return the current direction
  Future<CameraDirection> flipCamera() async {
    final result = await platformRun(
        androidFunction: _deepArPlatformHandler.flipCamera,
        iOSFunction: () => _deepArPlatformHandler.flipCameraIos(_textureId!));
    if (result != null && result) {
      _cameraDirection = _cameraDirection == CameraDirection.front
          ? CameraDirection.rear
          : CameraDirection.front;
      if (_cameraDirection == CameraDirection.front) _flashState = false;
    }
    return _cameraDirection;
  }

  ///Toggles flash and returns its status
  Future<bool> toggleFlash() async {
    bool result = await platformRun(
        androidFunction: _deepArPlatformHandler.toggleFlash,
        iOSFunction: () => _deepArPlatformHandler.toggleFlashIos(_textureId!));
    _flashState = result;
    return _flashState;
  }

  ///Fire named trigger of an fbx animation set on the currently loaded effect.
  Future<void> fireTrigger({required String trigger}) async {
    await platformRun(
        androidFunction: () => _deepArPlatformHandler.fireTrigger(trigger),
        iOSFunction: () =>
            _deepArPlatformHandler.fireTriggerIos(_textureId!, trigger));
  }

  ///Display debugging stats on screen.
  Future<void> showStats({required bool enabled}) async {
    await platformRun(
        androidFunction: () => _deepArPlatformHandler.showStats(enabled),
        iOSFunction: () =>
            _deepArPlatformHandler.showStatsIos(_textureId!, enabled));
  }

  ///Enable or disable global physics simulation.
  Future<void> simulatePhysics({required bool enabled}) async {
    await platformRun(
        androidFunction: () => _deepArPlatformHandler.simulatePhysics(enabled),
        iOSFunction: () =>
            _deepArPlatformHandler.simulatePhysicsIos(_textureId!, enabled));
  }

  ///Display physics colliders preview on screen.
  Future<void> showColliders({required bool enabled}) async {
    await platformRun(
        androidFunction: () => _deepArPlatformHandler.showColliders(enabled),
        iOSFunction: () =>
            _deepArPlatformHandler.showCollidersIos(_textureId!, enabled));
  }

  ///Releases all resources required by DeepAR.
  Future<void> destroy() async {
    await platformRun(
        androidFunction: _deepArPlatformHandler.destroy,
        iOSFunction: () => _deepArPlatformHandler.destroyIos(_textureId!));
  }

  ///Listen to native delegate methods
  void _setNativeListenerIos() {
    try {
      _deepArPlatformHandler.setListenerIos(_textureId!);
    } catch (e) {
      debugPrint(
          "Exception while setting iOS response listener, won't be able to notify flutter once files are available");
      debugPrint("Error $e");
    }
  }

  Future<bool> _askMediaPermission() async {
    await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (await Permission.camera.isGranted &&
        await Permission.microphone.isGranted) {
      return true;
    }

    return false;
  }
}
