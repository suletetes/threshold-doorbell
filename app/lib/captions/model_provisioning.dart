// On-device model provisioning state machine (Task 18, FR-5.2a, FR-10.1; AT-21).
// Privacy Mode transcribes on-device with a Whisper model that must be
// downloaded after explicit resident opt-in, showing the model size before
// download, and Privacy Mode stays unavailable and clearly labelled until the
// model is present and verified (FR-5.2a). A download SHALL NEVER occur during a
// live session (FR-5.2a). This is pure logic driven by fixture download progress
// so every transition and guard is unit-testable; the real download and Whisper
// verification bind to the AsrEngine interface (deferred to device).

import 'package:flutter/foundation.dart';

/// Provisioning lifecycle of the on-device speech model (FR-5.2a).
enum ModelState {
  /// The model is not on the device. Privacy Mode is unavailable (FR-5.2a).
  notPresent,

  /// The resident has opted in over the network; ready to download. The size
  /// is disclosed at this point (FR-5.2a).
  optIn,

  /// The download is in progress; progress and size are shown.
  downloading,

  /// The download finished and integrity verification is running.
  verifying,

  /// The model is present and verified. Privacy Mode becomes available.
  verified,

  /// Verification failed or the download errored; Privacy Mode stays
  /// unavailable and the resident can retry.
  failed,
}

/// Immutable snapshot of provisioning, including size disclosure and progress.
@immutable
class ModelProvisioning {
  const ModelProvisioning({
    required this.state,
    required this.sizeBytes,
    this.downloadedBytes = 0,
  });

  final ModelState state;

  /// The model download size in bytes, disclosed before download (FR-5.2a).
  final int sizeBytes;

  /// Bytes downloaded so far (0 until downloading).
  final int downloadedBytes;

  /// Privacy Mode is available ONLY when the model is verified (FR-5.2a).
  bool get privacyModeAvailable => state == ModelState.verified;

  /// A stable, dash-free label for the UI to show when Privacy Mode is not yet
  /// usable (FR-5.2a "clearly labelled as unavailable"). NFR-10 compliant.
  String get unavailabilityLabel {
    switch (state) {
      case ModelState.notPresent:
        return 'Privacy Mode needs an on device model. Download it to enable Privacy Mode.';
      case ModelState.optIn:
        return 'Ready to download the on device model.';
      case ModelState.downloading:
        return 'Downloading the on device model.';
      case ModelState.verifying:
        return 'Verifying the on device model.';
      case ModelState.failed:
        return 'The on device model could not be verified. Please try again.';
      case ModelState.verified:
        return 'Privacy Mode is available.';
    }
  }

  /// Download progress in [0, 1]; 0 outside the downloading state.
  double get progress {
    if (sizeBytes <= 0) return 0;
    final p = downloadedBytes / sizeBytes;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }

  ModelProvisioning copyWith({
    ModelState? state,
    int? sizeBytes,
    int? downloadedBytes,
  }) {
    return ModelProvisioning(
      state: state ?? this.state,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    );
  }
}

/// Raised when a download is attempted during a live session (FR-5.2a).
class DownloadDuringSessionError extends StateError {
  DownloadDuringSessionError()
      : super('The on device model cannot be downloaded during a live session');
}

/// Drives the provisioning lifecycle. The caller supplies whether a live session
/// is active so the machine can refuse a download mid-session (FR-5.2a).
class ModelProvisioningMachine {
  ModelProvisioningMachine({required int modelSizeBytes})
      : _p = ModelProvisioning(
            state: ModelState.notPresent, sizeBytes: modelSizeBytes);

  ModelProvisioning _p;
  ModelProvisioning get snapshot => _p;
  ModelState get state => _p.state;
  bool get privacyModeAvailable => _p.privacyModeAvailable;

  /// Resident opts in over the network. Size is disclosed here (FR-5.2a). Only
  /// valid from notPresent or failed (retry).
  void optIn() {
    if (_p.state == ModelState.notPresent || _p.state == ModelState.failed) {
      _p = _p.copyWith(state: ModelState.optIn, downloadedBytes: 0);
    }
  }

  /// Begin the download. Refused during a live session (FR-5.2a). Requires a
  /// prior opt-in (FR-5.2a "only after explicit resident opt-in").
  void startDownload({required bool liveSessionActive}) {
    if (liveSessionActive) {
      throw DownloadDuringSessionError();
    }
    if (_p.state != ModelState.optIn) {
      throw StateError('Download requires an explicit opt-in first');
    }
    _p = _p.copyWith(state: ModelState.downloading, downloadedBytes: 0);
  }

  /// Report download progress (bytes). Clamped to the model size.
  void onProgress(int downloadedBytes) {
    if (_p.state != ModelState.downloading) return;
    final clamped = downloadedBytes < 0
        ? 0
        : (downloadedBytes > _p.sizeBytes ? _p.sizeBytes : downloadedBytes);
    _p = _p.copyWith(downloadedBytes: clamped);
  }

  /// Download finished; move to verification.
  void onDownloadComplete() {
    if (_p.state != ModelState.downloading) return;
    _p =
        _p.copyWith(state: ModelState.verifying, downloadedBytes: _p.sizeBytes);
  }

  /// Verification result. Success enables Privacy Mode (FR-5.2a); failure keeps
  /// it unavailable and allows a retry from failed.
  void onVerified({required bool ok}) {
    if (_p.state != ModelState.verifying) return;
    _p = _p.copyWith(state: ok ? ModelState.verified : ModelState.failed);
  }

  /// Any download/verify error transitions to failed (retryable via optIn).
  void onError() {
    if (_p.state == ModelState.downloading ||
        _p.state == ModelState.verifying) {
      _p = _p.copyWith(state: ModelState.failed);
    }
  }
}
