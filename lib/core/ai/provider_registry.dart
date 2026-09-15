/// provider_registry.dart
/// AURA Assistant – Provider Registry
///
/// Defines AI provider presets with default settings, supported models,
/// and display information. Provider-agnostic architecture: user picks
/// provider, enters API key, selects model.
library;

import 'connection_type.dart';

/// A provider preset defining available configuration.
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.connectionType,
    required this.displayName,
    required this.defaultBaseUrl,
    required this.defaultModel,
    required this.supportedModels,
    this.icon = '🤖',
  });

  /// Unique identifier for this provider preset.
  final String id;

  /// The connection type this preset uses.
  final ConnectionType connectionType;

  /// Human-readable provider name (localized by UI).
  final String displayName;

  /// Default API base URL.
  final String defaultBaseUrl;

  /// Default model name.
  final String defaultModel;

  /// List of supported model names.
  final List<String> supportedModels;

  /// Emoji icon for visual identification.
  final String icon;

  /// Whether this preset allows custom base URL editing.
  bool get allowsCustomBaseUrl => connectionType == ConnectionType.customOpenAI;

  /// Whether this preset allows free-text model input.
  bool get allowsCustomModel => connectionType == ConnectionType.customOpenAI;
}

/// Registry of all available provider presets.
class ProviderRegistry {
  ProviderRegistry._();

  static const List<ProviderPreset> presets = [
    ProviderPreset(
      id: 'openai',
      connectionType: ConnectionType.openaiCompatible,
      displayName: 'OpenAI',
      defaultBaseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o-mini',
      supportedModels: [
        'gpt-4o',
        'gpt-4o-mini',
        'gpt-4-turbo',
        'gpt-3.5-turbo',
      ],
      icon: '🟢',
    ),
    ProviderPreset(
      id: 'gemini',
      connectionType: ConnectionType.gemini,
      displayName: 'Google Gemini',
      defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      defaultModel: 'gemini-2.0-flash',
      supportedModels: [
        'gemini-2.0-flash',
        'gemini-1.5-pro',
        'gemini-1.5-flash',
      ],
      icon: '🔵',
    ),
    ProviderPreset(
      id: 'custom',
      connectionType: ConnectionType.customOpenAI,
      displayName: 'Custom (OpenAI-Compatible)',
      defaultBaseUrl: '',
      defaultModel: '',
      supportedModels: [],
      icon: '⚙️',
    ),
  ];

  /// Find a preset by its connection type.
  static ProviderPreset? presetForType(ConnectionType type) {
    for (final preset in presets) {
      if (preset.connectionType == type) return preset;
    }
    return null;
  }

  /// Find a preset by its ID.
  static ProviderPreset? presetById(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// Get the default preset (OpenAI).
  static ProviderPreset get defaultPreset => presets.first;
}
