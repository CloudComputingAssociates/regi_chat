import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/input_mode.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart' show TtsService, TtsException;
import '../state/chat_state.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_output.dart';
import '../widgets/ptt_button.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chat = ChatService();
  final SpeechService _speech = SpeechService();
  final TtsService _tts = TtsService();
  StreamSubscription<String>? _speechSub;

  @override
  void initState() {
    super.initState();
    _speech.initialize();
  }

  @override
  void dispose() {
    _speechSub?.cancel();
    _speech.stop();
    _chat.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    final state = context.read<ChatState>();
    final auth = context.read<AuthService>();

    state.addMessage(TextMessage(content: text, role: MessageRole.user));

    final jwt = await auth.getAccessToken();
    if (jwt == null) {
      state.addMessage(TextMessage(
        content: '⚠️ Not authenticated. Please sign in again.',
        role: MessageRole.assistant,
      ));
      return;
    }

    final wasVoiceMode = state.mode == InputMode.voice;
    final stream = state.startAssistantStream();
    try {
      await for (final chunk in _chat.streamChat(
        message: text,
        sessionId: state.sessionId,
        jwt: jwt,
      )) {
        state.appendToStream(stream, chunk);
      }
      state.completeStream(stream);
    } catch (e) {
      state.appendToStream(stream, '\n[error: $e]');
      state.completeStream(stream);
      return;
    }

    // Speak the assistant reply only when the user is in voice mode.
    // In text mode they're reading; speaking would be intrusive.
    // POC: TTS failures are surfaced into the chat output as a visible log
    // line (even though the user is in voice mode, screen still shows them).
    if (wasVoiceMode && stream.content.trim().isNotEmpty) {
      final freshJwt = await auth.getAccessToken() ?? jwt;
      try {
        await _tts.speak(stream.content, jwt: freshJwt);
      } on TtsException catch (e) {
        if (!mounted) return;
        state.addMessage(TextMessage(
          content: '[tts] $e',
          role: MessageRole.assistant,
        ));
      }
    }
  }

  void _handlePromptMe() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('PromptMe mode: How can I help?'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleTalkStart() async {
    final state = context.read<ChatState>();
    if (state.isPromptMeOn) return;
    state.setTalkActive(true);
    state.setCurrentInput('');

    final ok = await _speech.initialize();
    if (!ok) return;

    _speechSub?.cancel();
    _speechSub = _speech.listen().listen((transcript) {
      if (!mounted) return;
      context.read<ChatState>().setCurrentInput(transcript);
    });
  }

  Future<void> _handleTalkEnd() async {
    final state = context.read<ChatState>();
    if (!state.isTalkActive) return;

    await _speech.stop();
    await _speechSub?.cancel();
    _speechSub = null;

    final transcript = state.currentInput.trim();
    state.setTalkActive(false);
    state.clearCurrentInput();

    if (transcript.isNotEmpty) {
      await _sendMessage(transcript);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChatState>();
    final showPtt =
        state.mode == InputMode.voice && !state.isPromptMeOn;

    return Scaffold(
      backgroundColor: const Color(0xFF1B1B1B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B1B),
        foregroundColor: Colors.white,
        title: const Text('RegiMenu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().logout(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const Expanded(child: ChatOutput()),
              ChatInput(
                onSend: _sendMessage,
                onPromptMe: _handlePromptMe,
                onTalkStart: _handleTalkStart,
                onTalkEnd: _handleTalkEnd,
              ),
            ],
          ),
          if (showPtt)
            Positioned(
              left: 0,
              right: 0,
              bottom: 140, // ~64dp bar + ~24dp safe area + ~52dp gap = ~3/4"
              child: Center(
                child: PttButton(
                  onPressStart: _handleTalkStart,
                  onPressEnd: _handleTalkEnd,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
