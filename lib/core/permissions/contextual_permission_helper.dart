// ───────────────────────────────────────────────────────────────────
// Step 5 – Runtime Permission Flows · Contextual Permission Helper
// ───────────────────────────────────────────────────────────────────
// High-level helper that wraps PermissionService with:
//   1. Rationale sheet (show before system dialog when appropriate)
//   2. Permanent-denial → open system settings flow
//   3. Multi-permission support (e.g., VisionScreen needs camera + mic)
//
// Screens should use this instead of calling PermissionService directly.
// ───────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'permission_service.dart';
import 'permission_rationale_sheet.dart';
import '../errors/result.dart';
import '../errors/failures.dart';
import '../../features/device_integration/domain/models/permission_status.dart';

/// Maps a [DevicePermission] to the corresponding [ph.Permission].
///
/// Some DevicePermissions (accessibility, overlay, screenCapture, assistant)
/// do not have a direct ph.Permission equivalent and require platform
/// channels — those map to null.
ph.Permission? devicePermissionToPH(DevicePermission dp) {
  switch (dp) {
    case DevicePermission.microphone:
      return ph.Permission.microphone;
    case DevicePermission.camera:
      return ph.Permission.camera;
    case DevicePermission.notification:
      return ph.Permission.notification;
    case DevicePermission.storage:
      return ph.Permission.storage;
    case DevicePermission.batteryOptimization:
      return ph.Permission.ignoreBatteryOptimizations;
    case DevicePermission.location:
      return ph.Permission.location;
    case DevicePermission.exactAlarm:
      return ph.Permission.scheduleExactAlarm;
    case DevicePermission.accessibility:
    case DevicePermission.overlay:
    case DevicePermission.screenCapture:
    case DevicePermission.assistant:
      return null; // platform-channel only
  }
}

/// Maps a [ph.PermissionStatus] to our [PermissionStatus].
PermissionStatus phStatusToLocal(ph.PermissionStatus status) {
  if (status.isGranted) return PermissionStatus.granted;
  if (status.isDenied) return PermissionStatus.denied;
  if (status.isPermanentlyDenied) return PermissionStatus.permanentlyDenied;
  if (status.isLimited) return PermissionStatus.granted; // treat limited as granted
  return PermissionStatus.unknown;
}

/// Outcome of a contextual permission request.
class ContextualPermissionOutcome {
  /// All requested permissions were granted.
  final bool allGranted;

  /// At least one permission was permanently denied.
  final bool hasPermanentlyDenied;

  /// Per-permission results.
  final Map<ph.Permission, bool> results;

  const ContextualPermissionOutcome({
    required this.allGranted,
    required this.hasPermanentlyDenied,
    required this.results,
  });
}

/// Wraps [PermissionService] with rationale UI and settings redirect.
///
/// Usage:
/// ```dart
/// final helper = ContextualPermissionHelper();
/// final outcome = await helper.requestWithRationale(
///   context: context,
///   permissions: [ph.Permission.microphone],
///   isCritical: true,
/// );
/// if (outcome.allGranted) { ... }
/// ```
class ContextualPermissionHelper {
  final PermissionService _service;

  ContextualPermissionHelper([PermissionService? service])
      : _service = service ?? PermissionService();

  /// Requests one or more permissions with the full rationale → request →
  /// permanent-denied → settings flow.
  ///
  /// For each permission:
  ///  1. Check if already granted → skip.
  ///  2. If [isCritical] or shouldShowRationale is true → show rationale sheet.
  ///  3. If user dismisses rationale → mark denied.
  ///  4. Request via system dialog.
  ///  5. If permanently denied → offer to open settings.
  ///
  /// Returns a [ContextualPermissionOutcome] summarizing results.
  Future<ContextualPermissionOutcome> requestWithRationale({
    required BuildContext context,
    required List<ph.Permission> permissions,
    bool isCritical = false,
  }) async {
    final results = <ph.Permission, bool>{};
    bool anyPermanentlyDenied = false;

    for (final permission in permissions) {
      // 1. Already granted?
      final alreadyGranted = await _service.isPermissionGranted(permission);
      if (alreadyGranted) {
        results[permission] = true;
        continue;
      }

      // 2. Show rationale for critical permissions or when the user
      //    previously denied (but not permanently).  On Android,
      //    shouldShowRequestRationale returns true after a soft denial.
      //    On iOS it always returns false.
      final shouldShow = isCritical ||
          await permission.shouldShowRequestRationale;

      if (shouldShow && context.mounted) {
        final userWantsToContinue =
            await showPermissionRationale(context, permission);
        if (!userWantsToContinue) {
          results[permission] = false;
          continue;
        }
      }

      // 3. Request via system dialog.
      if (!context.mounted) {
        results[permission] = false;
        continue;
      }

      final result = await _service.requestPermission(permission);
      final granted = result.isSuccess && result.getOrElse(() => false);
      results[permission] = granted;

      // 4. If permanently denied, offer to open settings.
      if (!granted && context.mounted) {
        final permanentlyDenied =
            await _service.isPermissionPermanentlyDenied(permission);
        if (permanentlyDenied) {
          anyPermanentlyDenied = true;
          // Offer to open settings — we don't await the return from settings
          // because the user may or may not grant. We just open it.
          final opened = await _service.openAppSettings();
          if (!opened) {
            // If settings can't be opened, at least we tried.
          }
        }
      }
    }

    return ContextualPermissionOutcome(
      allGranted: results.values.every((v) => v),
      hasPermanentlyDenied: anyPermanentlyDenied,
      results: results,
    );
  }

  /// Convenience for requesting a single permission.
  ///
  /// Returns true if granted, false otherwise.
  /// Automatically opens settings on permanent denial.
  Future<bool> requestSingleWithRationale({
    required BuildContext context,
    required ph.Permission permission,
    bool isCritical = false,
  }) async {
    final outcome = await requestWithRationale(
      context: context,
      permissions: [permission],
      isCritical: isCritical,
    );
    return outcome.allGranted;
  }
}

// shouldShowRequestRationale is provided by the permission_handler
// package's PermissionActions extension. No additional extension needed.
