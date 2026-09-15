/// speech_recognition_impl.dart
/// AURA Assistant – P0 Remediation: Real speech-to-text implementation.
///
/// CRITICAL FIX: Added finalResult filtering.
/// Before fix: onResult fired for EVERY recognition event (partial + final),
///   causing duplicate processing in Live Mode.
/// After fix: onResult only fires for final results. Optional onPartial
///   callback for UI display of interim results.
library;

import 'package:speech_to_text/speech_to_text.dart';

/// Real speech-to-text implementation wrapping the speech_to_text package.
class SpeechRecognitionServiceImpl {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize();
    return _initialized;
  }

  /// Start listening for speech input.
  ///
  /// [onResult] – Fires ONLY for final recognition results (no partials).
  /// [onPartial] – Optional, fires for partial/interim results (for UI display).
  /// [locale] – Locale ID for speech recognition (default: Kurdish Sorani).
  Future<void> startListening({
    required void Function(String text) onResult,
    void Function(String text)? onPartial,
    String locale = 'ku',
  }) async {
    if (!_initialized) {
      await initialize();
    }
    await _speech.listen(
      localeId: locale,
      onResult: (result) {
        // CRITICAL FIX: Only fire onResult for final results.
        // Before this fix, every partial result would trigger onResult,
        // causing duplicate processing in Live Mode orchestrator.
        if (result.finalResult) {
          onResult(result.recognizedWords);
        } else {
          // Partial result — send to optional callback for UI display.
          onPartial?.call(result.recognizedWords);
        }
      },
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }
}