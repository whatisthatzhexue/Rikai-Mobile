import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/capture_photo.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/capture_session.dart';
import '../../state/providers.dart';

class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key});

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  CameraController? _controller;
  bool _initializing = false;
  bool _capturing = false;
  bool _permissionDenied = false;
  bool _cameraUnavailable = false;
  bool _childPageOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (ref.read(captureSessionProvider).isEmpty) {
        await ref.read(captureStorageProvider).clearSessionDirectory();
      }
      await _initializeCamera();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    unawaited(_disposeCamera());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed &&
        !_childPageOpen &&
        _controller == null &&
        !_initializing) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    if (_initializing || _childPageOpen) return;
    _initializing = true;
    if (mounted) {
      setState(() {
        _error = null;
        _permissionDenied = false;
        _cameraUnavailable = false;
      });
    }
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _cameraUnavailable = true);
        return;
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      try {
        await controller.initialize();
      } catch (error) {
        await controller.dispose();
        rethrow;
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() {});
    } on CameraException catch (error) {
      final denied =
          error.code == 'CameraAccessDenied' ||
          error.code == 'CameraAccessDeniedWithoutPrompt' ||
          error.code == 'CameraAccessRestricted';
      if (mounted) {
        setState(() {
          _permissionDenied = denied;
          if (!denied) _cameraUnavailable = true;
          _error = denied ? null : (error.description ?? error.code);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _cameraUnavailable = true;
          _error = error.toString();
        });
      }
    } finally {
      _initializing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {
        // Camera teardown races with lifecycle transitions; best effort.
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      final stored = await ref
          .read(captureStorageProvider)
          .importPhoto(shot.path);
      try {
        await File(shot.path).delete();
      } catch (_) {
        // The session copy is authoritative.
      }
      if (!mounted) return;
      ref.read(captureSessionProvider.notifier).addPhotos([
        CapturePhoto(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          filePath: stored,
          source: CapturePhotoSource.camera,
          createdAt: DateTime.now(),
        ),
      ]);
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.description ?? error.code);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '拍照失败：$error');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _importPhotos() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (picked.isEmpty || !mounted) return;
      final storage = ref.read(captureStorageProvider);
      final photos = <CapturePhoto>[];
      for (final file in picked) {
        final stored = await storage.importPhoto(file.path);
        photos.add(
          CapturePhoto(
            id: '${DateTime.now().microsecondsSinceEpoch}_${photos.length}',
            filePath: stored,
            originalPath: file.path,
            source: CapturePhotoSource.gallery,
            createdAt: DateTime.now(),
          ),
        );
      }
      if (!mounted) return;
      ref.read(captureSessionProvider.notifier).addPhotos(photos);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '导入照片失败：$error');
    } finally {
      if (mounted) setState(() => _capturing = false);
      if (!_childPageOpen && _controller == null) {
        unawaited(_initializeCamera());
      }
    }
  }

  Future<void> _openPhotoSet() async {
    if (ref.read(captureSessionProvider).isEmpty) return;
    _childPageOpen = true;
    ref.read(captureSessionProvider.notifier).setCurrentIndex(0);
    await _disposeCamera();
    if (!mounted) return;
    await context.push('/photos');
    if (!mounted) return;
    _childPageOpen = false;
    await _initializeCamera();
  }

  Future<void> _openSettings() async {
    await ref.read(permissionServiceProvider).openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(captureSessionProvider).length;
    return Scaffold(
      backgroundColor: AppColors.cameraBackground,
      appBar: AppBar(title: const Text('拍照识别')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreview(),
          if (_error != null) _buildStatusBanner(_error!),
          if (_permissionDenied)
            _CameraUnavailable(
              title: '相机权限未授予',
              message: '请在系统设置中允许相机权限，或先从相册导入照片。',
              actionLabel: '去授权',
              onSettings: _openSettings,
              onGallery: _importPhotos,
            )
          else if (_cameraUnavailable)
            _CameraUnavailable(
              title: '相机不可用',
              message: _error ?? '没有可用的相机硬件。',
              actionLabel: '重试',
              onSettings: _initializeCamera,
              onGallery: _importPhotos,
            ),
          if (!_permissionDenied && !_cameraUnavailable)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildControls(count),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: AppColors.cameraBackground);
    }
    final size = controller.value.previewSize;
    if (size == null) {
      return CameraPreview(controller);
    }
    // Camera previewSize is sensor-oriented; swap for portrait fill.
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.height,
        height: size.width,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildControls(int count) {
    final enabled = _controller != null && !_capturing;
    return Container(
      decoration: const BoxDecoration(color: AppColors.cameraScrim),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CameraSideButton(
                icon: Icons.photo_library_outlined,
                label: '导入照片',
                onPressed: _capturing ? null : _importPhotos,
              ),
              _ShutterButton(
                enabled: enabled,
                capturing: _capturing,
                onPressed: _takePhoto,
              ),
              _PhotoCountButton(
                count: count,
                onPressed: count == 0 ? null : _openPhotoSet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(String message) {
    return Positioned(
      top: AppSpacing.md,
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.cameraControl),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.enabled,
    required this.capturing,
    required this.onPressed,
  });

  final bool enabled;
  final bool capturing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSizes.cameraShutter,
      height: AppSizes.cameraShutter,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cameraControl, width: 4),
            ),
            padding: const EdgeInsets.all(4),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cameraControl,
              ),
              child: capturing
                  ? const Center(
                      child: SizedBox(
                        width: AppSizes.cameraProgress,
                        height: AppSizes.cameraProgress,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraSideButton extends StatelessWidget {
  const _CameraSideButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSizes.cameraSideControlWidth,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.cameraControl,
          disabledForegroundColor: AppColors.cameraControl.withValues(
            alpha: 0.4,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizes.iconLarge),
            const SizedBox(height: AppSpacing.xxs),
            Text(label, style: const TextStyle(fontSize: AppTypography.title)),
          ],
        ),
      ),
    );
  }
}

class _PhotoCountButton extends StatelessWidget {
  const _PhotoCountButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSizes.cameraSideControlWidth,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.cameraControl,
              disabledForegroundColor: AppColors.cameraControl.withValues(
                alpha: 0.4,
              ),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.collections_outlined, size: AppSizes.iconLarge),
                SizedBox(height: AppSpacing.xxs),
                Text('照片集', style: TextStyle(fontSize: AppTypography.title)),
              ],
            ),
          ),
          if (count > 0)
            Positioned(
              top: 0,
              right: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxs,
                  vertical: 1,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: AppColors.cameraControl,
                    fontSize: AppTypography.title,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onSettings,
    required this.onGallery,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onSettings;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: AppColors.cameraScrim,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: AppColors.cameraControl,
                size: AppSizes.heroIcon,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.cameraControl,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.cameraControl,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onSettings,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.cameraControl,
                      side: const BorderSide(color: AppColors.cameraControl),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(actionLabel),
                  ),
                  FilledButton.icon(
                    onPressed: onGallery,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.cameraControl,
                      foregroundColor: AppColors.textPrimary,
                    ),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册导入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
