import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/input_mode.dart';

class ChatState extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  InputMode _mode = InputMode.text;
  bool _isPromptMeOn = false;
  bool _isTalkActive = false;
  String? _sessionId;
  String _currentInput = '';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  InputMode get mode => _mode;
  bool get isPromptMeOn => _isPromptMeOn;
  bool get isTalkActive => _isTalkActive;
  String? get sessionId => _sessionId;
  String get currentInput => _currentInput;

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
}
