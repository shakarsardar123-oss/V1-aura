/// connection_type.dart
/// AURA Assistant – Connection Type Enum
///
/// Defines the supported AI connection types.
/// Extended to support multiple providers: OpenAI, Gemini, and Custom OpenAI-compatible.
library;

/// Supported AI connection types.
enum ConnectionType {
  /// OpenAI official API.
  openaiCompatible,

  /// Google Gemini API (OpenAI-compatible endpoint).
  gemini,

  /// Custom OpenAI-compatible API (user-defined base URL).
  customOpenAI,
}
