import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:deepar_flutter_plus/deepar_flutter_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepAR Plus Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ARView(
        effect: 'YOUR_EFFECT_URL_HERE',
        thumbNail: '', // Add a placeholder image
      ),
    );
  }
}

class ARView extends StatefulWidget {
  final String effect;
  final String thumbNail;

  const ARView({
    super.key,
    required this.effect,
    required this.thumbNail,
  });

  @override
  State<ARView> createState() => _ARViewState();
}

class _ARViewState extends State<ARView> {
  late final DeepArControllerPlus _controller;
  bool _isInitialized = false;
  double _downloadProgress = 0;
  StreamSubscription? _downloadSubscription;

  @override
  void initState() {
    _controller = DeepArControllerPlus();
    _checkPermissionsAndInitialize();

    super.initState();
  }

  Future<void> _checkPermissionsAndInitialize() async {
    // Request camera and microphone permissions
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();

    if (cameraStatus.isGranted && microphoneStatus.isGranted) {
      await _initializeAR();
      if (Platform.isIOS) {
        // Delay for iOS to ensure platform view is ready
        Future.delayed(const Duration(seconds: 2), () {
          _cancelDownload();
          _switchEffect();
        });
      }
    } else {
      // Handle case when permissions are not granted
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera and microphone access is required for AR features',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void didUpdateWidget(ARView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect != widget.effect) {
      // Cancel any ongoing download
      _cancelDownload();
      _switchEffect();
    }
  }

  void _cancelDownload() {
    _downloadProgress = 0;
    _downloadSubscription?.cancel();
    _downloadSubscription = null;
  }

  Future<void> _switchEffect() async {
    if (!mounted) return;

    setState(() {
      _isInitialized = false;
    });

    final fileStream = DefaultCacheManager().getFileStream(
      widget.effect,
      withProgress: true,
    );

    _downloadSubscription = fileStream.listen(
      (result) async {
        if (result is DownloadProgress) {
          if (mounted) {
            setState(() {
              _downloadProgress = result.progress ?? 0;
            });
          }
          log('Download progress: ${result.progress}');
        } else if (result is FileInfo) {
          try {
            await _controller.switchEffect(result.file.path);
            if (mounted) {
              setState(() {
                _isInitialized = true;
              });
            }
          } catch (e) {
            log('Error switching effect: $e');
            if (mounted) {
              setState(() {
                _isInitialized = true;
              });
            }
          }
        }
      },
      onError: (e) {
        log('Error downloading effect: $e');
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      },
      onDone: () {
        _downloadSubscription = null;
      },
    );
  }

  Future<void> _initializeAR() async {
    if (!mounted) return;

    try {
      final result = await _controller.initialize(
        androidLicenseKey: "YOUR-ANDROID-LICENSE-KEY",
        iosLicenseKey: "YOUR-IOS-LICENSE-KEY",
        resolution: Resolution.medium,
      );

      log('AR initialization result: ${result.success}, message: ${result.message}');

      if (result.success) {
        await _switchEffect();
      } else {
        log('Failed to initialize AR: ${result.message}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to initialize AR: ${result.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, s) {
      log('Error initializing AR: $e', stackTrace: s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing AR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _cancelDownload();
    _controller.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    log('AR View initialized: $_isInitialized');

    return Scaffold(
      body: Stack(
        children: [
          Transform.scale(
            scale: _controller.aspectRatio * 1.3,
            child: DeepArPreviewPlus(
              _controller,
              onViewCreated: () {
                if (Platform.isIOS) {
                  setState(() {
                    _isInitialized = true;
                  });
                }
              },
            ),
          ),
          if (!_isInitialized)
            ThumbnailLoaderImage(
              downloadProgress: _downloadProgress,
              thumbNail: widget.thumbNail,
            ),
        ],
      ),
    );
  }
}

class ThumbnailLoaderImage extends StatelessWidget {
  const ThumbnailLoaderImage({
    super.key,
    required this.downloadProgress,
    required this.thumbNail,
  });

  final double downloadProgress;

  final String thumbNail;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Thumbnail background (if available)
          if (thumbNail.isNotEmpty)
            Center(
              child: Image.asset(
                thumbNail,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            )
          else
            const Icon(
              Icons.image,
              size: 300,
            ),
          // Loading overlay
          Center(
            child: downloadProgress > 0
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          value: downloadProgress,
                          backgroundColor: Colors.black87,
                          strokeWidth: 4,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.deepPurple,
                          ),
                        ),
                      ),
                      Positioned(
                        child: Text(
                          '${(downloadProgress * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.deepPurple,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
