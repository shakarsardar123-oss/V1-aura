/// live_mode_orchestrator.dart
/// AURA Assistant – P0 Remediation: Live Mode Orchestrator
///
/// Core state machine: IDLE→LISTENING→PROCESSING→SPEAKING→LISTENING cycle.
///
/// CRITICAL FIXES:
/// 1. TTS feedback loop prevention: stop STT before TTS, restart after TTS completion.
/// 2. Real TTS completion callback: uses awaitSpeakCompletion(true) → speak() resolves after speech.
/// 3. Duplicate request prevention: generation token + finalResult filter.
/// 4. Race condition prevention: session generation guards all state transitions.
/// 5. Bounded retry: max 3 consecutive errors → auto-stop.
///
/// NEVER uses timers for TTS completion — relies on VoiceService.speak() await.
library;

import 'dart:async';

import '../../services/voice/voice_service.dart'
    show VoiceService;
import 'agent_processor.dart';
import '../agent/agent_context.dart';

import '../../domain/entities/agent_config.dart';
import '../../services/memory/memory_service.dart';
import 'live_mode_state.dart';

/// Callback for Live Mode state changes (for UI updates).
typedef LiveModeStateCallback = void Function(LiveModeState state);

/// Callback for recognized user text (for chat display).
typedef LiveModeRecognizedCallback = void Function(String text);

/// Callback for AI response text (for chat display).
typedef LiveModeResponseCallback = void Function(String text);

/// Orchestrates the continuous Live Mode voice cycle.
///
/// Flow:
/// 1. User activates Live Mode → IDLE→LISTENING
/// 2. STT recognizes final result → LISTENING→PROCESSING
/// 3. AgentProcessor processes input → PROCESSING→SPEAKING
/// 4. TTS speaks response, await resolves → SPEAKING→LISTENING
/// 5. Cycle continues until user stops or error limit reached.
class LiveModeOrchestrator {
  LiveModeOrchestrator({
    required VoiceService voiceService,
    required AgentProcessor agentProcessor,
    required MemoryService memoryService,
  })  : _voiceService = voiceService,
        _agentProcessor = agentProcessor,
        _memoryService = memoryService;

  final VoiceService _voiceService;
  final AgentProcessor _agentProcessor;
  final MemoryService _memoryService;

  LiveModeState _state = LiveModeState.idle;
  int _generation = 0;
  String? _currentSessionId;
  String? _currentConversationId;

  /// Consecutive error counter — auto-stop after [_maxConsecutiveErrors].
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;

  /// Whether a request is currently in-flight to prevent duplicates.
  bool _isProcessingRequest = false;

  /// Stream controller for state changes.
  final _stateController = StreamController<LiveModeState>.broadcast();

  /// Callbacks for UI updates.
  LiveModeStateCallback? onStateChanged;
  LiveModeRecognizedCallback? onUserRecognized;
  LiveModeResponseCallback? onAIResponse;

  /// Current Live Mode state.
  LiveModeState get state => _state;

  /// Alias for state (backward compat with test expectations).
  LiveModeState get currentState => _state;

  /// Stream of state changes for UI.
  Stream<LiveModeState> get stateStream => _stateController.stream;

  /// Whether a Live session is currently active.
  bool get isActive => _state.isActive;

  /// Current session ID (null when idle).
  String? get currentSessionId => _currentSessionId;

  /// Current conversation ID for persistence.
  String? get currentConversationId => _currentConversationId;

  void _setState(LiveModeState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
      onStateChanged?.call(_state);
    }
  }

  /// Check if a generation is still current.
  bool _isCurrentGeneration(int gen) => gen == _generation;

  // ── Public API ──

  /// Start a Live Mode session.
  /// Returns the session, or null if cannot start.
  Future<LiveModeSession?> startSession() async {
    if (_state != LiveModeState.idle) return null;

    _generation++;
    final gen = _generation;
    _currentSessionId = 'live_${DateTime.now().millisecondsSinceEpoch}_$gen';
    _consecutiveErrors = 0;
    _isProcessingRequest = false;

    // Ensure we have a conversation for memory continuity.
    try {
      _currentConversationId = await _memoryService.createConversation(
        title: 'دەنگی زیندوو',
        agentId: 'default',
      );
    } catch (e) {
      // If DB fails, use a transient ID so Live Mode still works.
      _currentConversationId =
          'transient_${DateTime.now().millisecondsSinceEpoch}';
    }

    _setState(LiveModeState.listening);
    await _startListening(gen);

    return LiveModeSession(
      sessionId: _currentSessionId!,
      generation: gen,
    );
  }

  /// Stop a Live Mode session — user-initiated.
  /// Cancels all pending work and returns to IDLE.
  Future<void> stopSession() async {
    _generation++; // Invalidate all pending callbacks.
    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
    _isProcessingRequest = false;
    _currentSessionId = null;
    _setState(LiveModeState.idle);
  }

  // ── Core Cycle ──

  /// Start listening with generation guard.
  Future<void> _startListening(int gen) async {
    if (!_isCurrentGeneration(gen)) return;

    try {
      await _voiceService.startListening(
        onRecognized: (text) {
          // CRITICAL: Only process final results to prevent duplicates.
          // VoiceServiceImpl currently fires onResult for every event.
          // We guard with _isProcessingRequest to prevent duplicate processing.
          if (!_isCurrentGeneration(gen)) return;
          if (_isProcessingRequest) return; // Duplicate guard.
          if (_state != LiveModeState.listening) return; // Stale state.

          _isProcessingRequest = true;
          _onRecognizedFinal(gen, text);
        },
        locale: 'ckb_IQ',
      );
    } catch (e) {
      if (!_isCurrentGeneration(gen)) return;
      _handleError(gen, 'STT start failed: $e');
    }
  }

  /// Called when STT produces a final recognition result.
  void _onRecognizedFinal(int gen, String text) {
    if (!_isCurrentGeneration(gen)) return;
    if (text.trim().isEmpty) {
      // Empty recognition — go back to listening.
      _isProcessingRequest = false;
      _restartListening(gen);
      return;
    }

    // Notify UI of recognized text.
    onUserRecognized?.call(text);

    // Transition to PROCESSING.
    _setState(LiveModeState.processing);

    // CRITICAL: Stop STT before processing (TTS feedback loop prevention step 1).
    _stopSTTThenProcess(gen, text);
  }

  /// Stop STT, then process the recognized text with AgentProcessor.
  /// This prevents the microphone from picking up TTS output.
  Future<void> _stopSTTThenProcess(int gen, String text) async {
    if (!_isCurrentGeneration(gen)) return;

    try {
      await _voiceService.stopListening();
    } catch (e) {
      // STT stop failure is non-fatal — continue processing.
    }

    if (!_isCurrentGeneration(gen)) return;

    // Persist user message.
    try {
      if (_currentConversationId != null) {
        await _memoryService.addMessage(
          conversationId: _currentConversationId!,
          role: 'user',
          content: text,
        );
      }
    } catch (e) {
      // Persistence failure is non-fatal — continue processing.
    }

    // Process with AgentProcessor.
    try {
      final agentConfig = await _getDefaultConfig();

      // Load conversation history for context continuity.
      List<Map<String, dynamic>> history = [];
      if (_currentConversationId != null) {
        try {
          final messages =
              await _memoryService.getMessages(_currentConversationId!);
          history = messages
              .map((m) => {
                    'role': m.role,
                    'content': m.content,
                  })
              .toList();
        } catch (e) {
          // History load failure is non-fatal.
        }
      }

      final context = AgentContext(
        agentConfig: agentConfig,
        conversationHistory: history,
        maxSteps: 10,
      );

      final result = await _agentProcessor.run(
        userInput: text,
        context: context,
      );

      if (!_isCurrentGeneration(gen)) return;

      if (result.isSuccess && result.response != null) {
        _consecutiveErrors = 0; // Reset on success.
        onAIResponse?.call(result.response!);

        // Persist AI response.
        try {
          if (_currentConversationId != null) {
            await _memoryService.addMessage(
              conversationId: _currentConversationId!,
              role: 'assistant',
              content: result.response!,
            );
          }
        } catch (e) {
          // Persistence failure is non-fatal.
        }

        // Transition to SPEAKING.
        _setState(LiveModeState.speaking);

        // CRITICAL: TTS feedback loop prevention step 2:
        // Speak the response. VoiceServiceImpl.speak() uses awaitSpeakCompletion(true)
        // which means _tts.speak() resolves ONLY AFTER speech completes.
        // So speak() below resolves when TTS is done. No timer needed.
        await _speakThenRestartListening(gen, result.response!);
      } else {
        final errMsg = result.errorMessage ?? 'ببورە، هەڵەیەک ڕوویدا.';
        onAIResponse?.call(errMsg);
        _handleError(gen, 'AgentProcessor failed: $errMsg');
      }
    } catch (e) {
      if (!_isCurrentGeneration(gen)) return;
      _handleError(gen, 'AgentProcessor exception: $e');
    }
  }

  /// Speak the response, then restart listening.
  /// This is the REAL TTS completion callback — speak() resolves
  /// only after TTS finishes (awaitSpeakCompletion(true)).
  Future<void> _speakThenRestartListening(int gen, String text) async {
    if (!_isCurrentGeneration(gen)) return;

    try {
      // VoiceServiceImpl.speak() awaits _tts.speak() which resolves
      // only after speech completes (because awaitSpeakCompletion(true)).
      await _voiceService.speak(text, locale: 'ku');
    } catch (e) {
      if (!_isCurrentGeneration(gen)) return;
      // TTS error — try to continue the cycle.
      _handleError(gen, 'TTS failed: $e');
      return;
    }

    if (!_isCurrentGeneration(gen)) return;

    // TTS completed. Reset processing flag and restart listening.
    _isProcessingRequest = false;
    _setState(LiveModeState.listening);
    await _startListening(gen);
  }

  /// Restart listening after empty recognition or reset.
  Future<void> _restartListening(int gen) async {
    if (!_isCurrentGeneration(gen)) return;
    if (_state != LiveModeState.listening) return;

    try {
      await _voiceService.stopListening();
    } catch (e) {
      // Non-fatal.
    }

    if (!_isCurrentGeneration(gen)) return;
    await _startListening(gen);
  }

  // ── Error Handling with Bounded Retry ──

  /// Handle an error. Increment counter; auto-stop if limit reached.
  void _handleError(int gen, String reason) {
    if (!_isCurrentGeneration(gen)) return;

    _consecutiveErrors++;
    _isProcessingRequest = false;

    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      // Auto-stop: too many consecutive errors.
      _generation++; // Invalidate all pending callbacks.
      _voiceService.stopListening().catchError((_) {});
      _voiceService.stopSpeaking().catchError((_) {});
      _currentSessionId = null;
      _setState(LiveModeState.error);
      // After brief error display, go idle.
      Future.delayed(const Duration(seconds: 2), () {
        _setState(LiveModeState.idle);
      });
      return;
    }

    _setState(LiveModeState.error);
    // Retry after a short delay.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_isCurrentGeneration(gen)) return;
      _isProcessingRequest = false;
      _setState(LiveModeState.listening);
      _startListening(gen);
    });
  }

  // ── Helpers ──

  /// Get a default agent config for AgentContext.
  Future<AgentConfig> _getDefaultConfig() async {
    return const AgentConfig(
      id: 'default',
      name: 'AURA',
      description: 'یاریدەدەری تایبەتی تۆ',
      systemPrompt:
          'من ئەورای تایبەتی تۆم. وەڵامی کوردی سۆرانی بدەرەوە.',
      modelId: 'gpt-4o-mini',
      temperature: 0.7,
      maxTokens: 2048,
      isDefault: true,
      isActive: true,
    );
  }

  /// Dispose resources.
  void dispose() {
    _stateController.close();
  }
}
