import 'package:flutter/widgets.dart';

enum MessageRole { user, assistant }

sealed class ChatMessage {
  ChatMessage({DateTime? timestamp, required this.role})
      : timestamp = timestamp ?? DateTime.now();

  final DateTime timestamp;
  final MessageRole role;
}

class TextMessage extends ChatMessage {
  TextMessage({required this.content, required super.role, super.timestamp});

  final String content;
}

class StreamingTextMessage extends ChatMessage {
  StreamingTextMessage({
    String content = '',
    this.isComplete = false,
    required super.role,
    super.timestamp,
  }) : _buffer = StringBuffer(content);

  final StringBuffer _buffer;
  bool isComplete;

  String get content => _buffer.toString();

  void append(String chunk) {
    _buffer.write(chunk);
  }

  TextMessage finalize() {
    isComplete = true;
    return TextMessage(content: content, role: role, timestamp: timestamp);
  }
}

class ChoiceMessage extends ChatMessage {
  ChoiceMessage({
    required this.prompt,
    required this.choices,
    required this.onSelect,
    required super.role,
    super.timestamp,
  });

  final String prompt;
  final List<String> choices;
  final void Function(String) onSelect;
}

class OverlayMessage extends ChatMessage {
  OverlayMessage({
    required this.overlayContent,
    required super.role,
    super.timestamp,
  });

  final Widget overlayContent;
}

class VoiceMessage extends ChatMessage {
  VoiceMessage({
    required this.spokenText,
    this.audioUrl,
    required super.role,
    super.timestamp,
  });

  final String spokenText;
  final String? audioUrl;
}
