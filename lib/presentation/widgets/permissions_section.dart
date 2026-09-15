// ───────────────────────────────────────────────────────────────────
// Permissions Section Widget — Rebuilt with glass design
// ───────────────────────────────────────────────────────────────────
// Uses GlassCard wrapper + dark background styling.
// Preserves all runtime permission logic (P0 safe).
// ───────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:aura_assistant/l10n/app_localizations.dart';
import 'package:aura_assistant/features/device_integration/domain/models/permission_status.dart';
import 'package:aura_assistant/features/central_permissions/presentation/permission_status_card.dart';
import 'package:aura_assistant/core/permissions/contextual_permission_helper.dart';
import 'package:aura_assistant/core/theme/app_colors.dart';

class _CheckablePermissions {
  static const list = <DevicePermission>[
    DevicePermission.microphone,
    DevicePermission.camera,
    DevicePermission.notification,
    DevicePermission.storage,
    DevicePermission.batteryOptimization,
    DevicePermission.location,
    DevicePermission.exactAlarm,
  ];
}

class _SystemPermissions {
  static const list = <DevicePermission>[
    DevicePermission.accessibility,
    DevicePermission.overlay,
    DevicePermission.screenCapture,
    DevicePermission.assistant,
  ];
}

class PermissionsSection extends ConsumerStatefulWidget {
  const PermissionsSection({super.key});

  @override
  ConsumerState<PermissionsSection> createState() =>
      _PermissionsSectionState();
}

class _PermissionsSectionState extends ConsumerState<PermissionsSection> {
  Map<DevicePermission, PermissionStatus> _statuses = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllStatuses();
  }

  Future<void> _loadAllStatuses() async {
    final statuses = <DevicePermission, PermissionStatus>{};

    for (final dp in _CheckablePermissions.list) {
      final phPerm = devicePermissionToPH(dp);
      if (phPerm != null) {
        final rawStatus = await phPerm.status;
        statuses[dp] = phStatusToLocal(rawStatus);
      } else {
        statuses[dp] = PermissionStatus.unknown;
      }
    }

    for (final dp in _SystemPermissions.list) {
      final phPerm = devicePermissionToPH(dp);
      if (phPerm != null) {
        final rawStatus = await phPerm.status;
        statuses[dp] = phStatusToLocal(rawStatus);
      } else {
        statuses[dp] = PermissionStatus.notRequested;
      }
    }

    if (mounted) {
      setState(() {
        _statuses = statuses;
        _loading = false;
      });
    }
  }

  Future<void> _requestPermission(DevicePermission dp) async {
    final phPerm = devicePermissionToPH(dp);
    if (phPerm == null) {
      await ph.openAppSettings();
      return;
    }

    final permHelper = ContextualPermissionHelper();
    await permHelper.requestSingleWithRationale(
      context: context,
      permission: phPerm,
      isCritical: true,
    );

    await _loadAllStatuses();
  }

  Future<void> _openSettings(DevicePermission dp) async {
    await ph.openAppSettings();
    await _loadAllStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.cyan,
          ),
        ),
      );
    }

    final checkableCards = _CheckablePermissions.list.map((dp) {
      final status = _statuses[dp] ?? PermissionStatus.unknown;
      return PermissionStatusCard(
        permission: dp,
        status: status,
        onRequest: status == PermissionStatus.granted
            ? null
            : () => _requestPermission(dp),
        onOpenSettings: status == PermissionStatus.permanentlyDenied
            ? () => _openSettings(dp)
            : null,
      );
    }).toList();

    final systemCards = _SystemPermissions.list.map((dp) {
      final status = _statuses[dp] ?? PermissionStatus.notRequested;
      return PermissionStatusCard(
        permission: dp,
        status: status,
        onRequest: () => _openSettings(dp),
        onOpenSettings: () => _openSettings(dp),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkable permissions
        ...checkableCards,

        // Divider between sections
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Container(
            height: 0.5,
            color: AppColors.glassBorder,
          ),
        ),

        // System permissions subheader
        Padding(
          padding: EdgeInsets.fromLTRB(
            isRtl ? 0 : 20,
            4,
            isRtl ? 20 : 0,
            8,
          ),
          child: Text(
            s.perm_open_settings,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.hint,
            ),
          ),
        ),

        // System permissions
        ...systemCards,

        const SizedBox(height: 8),
      ],
    );
  }
}
