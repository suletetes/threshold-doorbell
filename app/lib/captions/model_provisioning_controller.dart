// On-device model provisioning controller (Task 18, FR-5.2a).
//
// Wraps [ModelProvisioningMachine] in a [ChangeNotifier] so Riverpod widgets
// can watch provisioning state and rebuild on transitions. This is the single
// place the UI drives the machine; everything else is read-only.
//
// The real download and Whisper verification are deferred to device adapters.
// In this build the controller simulates a download for demo purposes so the
// UI state machine is fully exercisable without a real model file. The
// simulation is gated behind [_kSimulateDownload] which is only true in the
// demo build; a real build will inject a [ModelDownloadPort] here.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'model_provisioning.dart';

/// Whether to run the demo download simulation instead of a real download.
/// Set to true here so the UI is exercisable in the hackathon demo build.
const bool _kSimulateDownload = true;

/// Drives the [ModelProvisioningMachine] and notifies listeners on every
/// transition (FR-5.2a). Consumed by Riverpod as a [ChangeNotifier].
class ModelProvisioningController extends ChangeNotifier {
  ModelProvisioningController({required int modelSizeBytes})
      : _machine = ModelProvisioningMachine(modelSizeBytes: modelSizeBytes);

  final ModelProvisioningMachine _machine;
  Timer? _simulationTimer;
  bool _sessionActive = false;

  /// The latest immutable snapshot of provisioning state.
  ModelProvisioning get snapshot => _machine.snapshot;

  /// The underlying machine. Exposed so the session coordinator can read live
  /// provisioning state from the same instance the download sheet drives.
  ModelProvisioningMachine get machine => _machine;

  /// Current state shorthand.
  ModelState get state => _machine.state;

  /// True once the model is present and verified (FR-5.2a).
  bool get privacyModeAvailable => _machine.privacyModeAvailable;

  /// Called by the session layer when a live session starts or ends, so the
  /// machine can refuse a download mid-session (FR-5.2a).
  set sessionActive(bool value) {
    _sessionActive = value;
  }

  /// Resident opts in to download. Discloses the model size (FR-5.2a).
  /// Only valid from [ModelState.notPresent] or [ModelState.failed].
  void optIn() {
    _machine.optIn();
    notifyListeners();
  }

  /// Begin the download. Throws [DownloadDuringSessionError] when a live
  /// session is active (FR-5.2a).
  Future<void> startDownload() async {
    _machine.startDownload(liveSessionActive: _sessionActive);
    notifyListeners();

    if (_kSimulateDownload) {
      await _runSimulatedDownload();
    }
    // In a real build: inject a ModelDownloadPort and drive the machine from
    // its progress stream here.
  }

  /// Simulates a download with incremental progress ticks so the progress bar
  /// and state transitions are exercisable in the demo build.
  Future<void> _runSimulatedDownload() async {
    final size = snapshot.sizeBytes;
    const steps = 40;
    const stepDuration = Duration(milliseconds: 80);
    final stepBytes = (size / steps).round();

    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(stepDuration);
      if (!_machine.state.isDownloading) return; // cancelled or errored
      _machine.onProgress(stepBytes * i);
      notifyListeners();
    }

    _machine.onDownloadComplete();
    notifyListeners();

    // Brief verification pause.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_machine.state != ModelState.verifying) return;

    _machine.onVerified(ok: true);
    notifyListeners();
  }

  /// Cancel a download in progress (not in the machine spec but useful for UI).
  void cancelDownload() {
    if (_machine.state == ModelState.downloading ||
        _machine.state == ModelState.verifying) {
      _machine.onError();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}

extension on ModelState {
  bool get isDownloading => this == ModelState.downloading;
}
