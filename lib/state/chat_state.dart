import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/input_mode.dart';
import '../models/voice_option.dart';

class ChatState extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  InputMode _mode = InputMode.text;
  bool _isPromptMeOn = false;
  bool _isTalkActive = false;
  String? _sessionId;
  String _currentInput = '';
  List<VoiceOption> _availableVoices = const [];
  VoiceOption? _selectedVoice;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  InputMode get mode => _mode;
  bool get isPromptMeOn => _isPromptMeOn;
  bool get isTalkActive => _isTalkActive;
  String? get sessionId => _sessionId;
  String get currentInput => _currentInput;
  List<VoiceOption> get availableVoices => _availableVoices;
  VoiceOption? get selectedVoice => _selectedVoice;

  void setMode(InputMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  void togglePromptMe() {
    _isPromptMeOn = !_isPromptMeOn;
    if (_isPromptMeOn && _isTalkActive) {
      _isTalkActive = false;
    }
    notifyListeners();
  }

  void setTalkActive(bool active) {
    if (_isTalkActive == active) return;
    if (active && _isPromptMeOn) return;
    _isTalkActive = active;
    notifyListeners();
  }

  void setCurrentInput(String value) {
    _currentInput = value;
    notifyListeners();
  }

  void clearCurrentInput() {
    if (_currentInput.isEmpty) return;
    _currentInput = '';
    notifyListeners();
  }

  void setSessionId(String? id) {
    _sessionId = id;
    notifyListeners();
  }

  void addMessage(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  StreamingTextMessage startAssistantStream() {
    final msg = StreamingTextMessage(role: MessageRole.assistant);
    _messages.add(msg);
    notifyListeners();
    return msg;
  }

  void appendToStream(StreamingTextMessage msg, String chunk) {
    msg.append(chunk);
    notifyListeners();
  }

  void completeStream(StreamingTextMessage msg) {
    msg.isComplete = true;
    notifyListeners();
  }

  /// Replaces the available voice list. Defaults [_selectedVoice] to the first
  /// entry when no voice is currently selected (or when the previously
  /// selected one is no longer in the catalog).
  void setAvailableVoices(List<VoiceOption> voices) {
    _availableVoices = List.unmodifiable(voices);
    if (voices.isEmpty) {
      _selectedVoice = null;
    } else if (_selectedVoice == null ||
        !voices.any((v) => v.id == _selectedVoice!.id)) {
      _selectedVoice = voices.first;
    }
    notifyListeners();
  }

  void setSelectedVoice(VoiceOption voice) {
    if (_selectedVoice?.id == voice.id) return;
    _selectedVoice = voice;
    notifyListeners();
  }

  /// Clears the visible conversation and detaches from the server-side
  /// session so the next user message starts a fresh chat. The server's
  /// stored history for the prior session is left intact (it will idle out
  /// or be reusable later); Flutter just stops referencing it.
  /// Voice selection and input mode are preserved.
  void clearChat() {
    _messages.clear();
    _sessionId = null;
    _currentInput = '';
    _isPromptMeOn = false;
    _isTalkActive = false;
    notifyListeners();
  }
}
