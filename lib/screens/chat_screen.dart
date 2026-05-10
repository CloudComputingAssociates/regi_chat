import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/input_mode.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/tts_service.dart' show TtsService, TtsException;
import '../services/web_speech_service.dart';
import '../state/chat_state.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_output.dart';
import '../widgets/mic_level_bars.dart';
import '../widgets/ptt_button.dart';
import '../widgets/voice_picker.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chat = ChatService();
  final WebSpeechService _speech = WebSpeechService();
  final TtsService _tts = TtsService();
  StreamSubscription<String>? _speechSub;

  // Prepended to EVERY user message — models drift mid-session and stop
  // honoring a one-shot directive after a few turns. Stricter wording too.
  static const _conciseDirective =
      'Reply in 1-2 sentences, max 30 words. No preamble or filler. ';

  @override
  void initState() {
    super.initState();
    _speech.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVoices());
  }

  Future<void> _loadVoices() async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final jwt = await auth.getAccessToken();
    if (jwt == null || !mounted) return;
    final voices = await _tts.fetchVoices(jwt: jwt);
    if (!mounted) return;
    context.read<ChatState>().setAvailableVoices(voices);
  }

  @override
  void dispose() {
    _speechSub?.cancel();
    _speech.stop();
    _speech.dispose();
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
        content: 'Not authenticated. Please sign in again.',
        role: MessageRole.assistant,
      ));
      return;
    }

    final messageToSend = '$_conciseDirective$text';

    final stream = state.startAssistantStream();
    String? lastSessionStatus;
    try {
      await for (final chunk in _chat.streamChat(
        message: messageToSend,
        sessionId: state.sessionId,
        jwt: jwt,
      )) {
        if (chunk.sessionId != null && chunk.sessionId != state.sessionId) {
          state.setSessionId(chunk.sessionId);
        }
        if (chunk.sessionStatus != null) {
          lastSessionStatus = chunk.sessionStatus;
        }
        if (chunk.hasError) {
          state.appendToStream(stream, '\n[error: ${chunk.error}]');
        }
        if (chunk.hasDelta) {
          state.appendToStream(stream, chunk.delta!);
        }
      }
      state.completeStream(stream);
    } catch (e) {
      state.appendToStream(stream, '\n[error: $e]');
      state.completeStream(stream);
      return;
    }

    if (lastSessionStatus != null && lastSessionStatus != 'ACTIVE') {
      state.setSessionId(null);
      if (mounted) {
        state.addMessage(TextMessage(
          content: '[session $lastSessionStatus — starting new conversation]',
          role: MessageRole.assistant,
        ));
      }
    }

    if (state.ttsEnabled && stream.content.trim().isNotEmpty) {
      final replyText = stream.content;
      final voiceId = state.selectedVoice?.id;
      final rate = state.ttsRate;
      unawaited(() async {
        final freshJwt = await auth.getAccessToken() ?? jwt;
        try {
          await _tts.speak(
            replyText,
            jwt: freshJwt,
            voice: voiceId,
            speakingRate: rate,
          );
        } on TtsException catch (e) {
          if (!mounted) return;
          context.read<ChatState>().addMessage(TextMessage(
                content: '[tts] $e',
                role: MessageRole.assistant,
              ));
        }
      }());
    }
  }

  Future<void> _handleNewChat() async {
    final state = context.read<ChatState>();
    if (state.messages.isEmpty && state.sessionId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: const Text(
          'Start a new chat?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'The current conversation will clear from this view. '
          'Server-side history is preserved.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B1A2B),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('New chat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final priorSessionId = state.sessionId;
    final auth = context.read<AuthService>();

    context.read<ChatState>().clearChat();

    if (priorSessionId != null && priorSessionId.isNotEmpty) {
      unawaited(() async {
        final jwt = await auth.getAccessToken();
        if (jwt == null) return;
        await _chat.closeSession(sessionId: priorSessionId, jwt: jwt);
      }());
    }
  }

  Future<void> _handleTalkStart() async {
    final state = context.read<ChatState>();
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
    final showPtt = state.mode == InputMode.voice;

    return Scaffold(
      backgroundColor: const Color(0xFF1B1B1B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B1B),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Text('RegiMenu'),
            const SizedBox(width: 12),
            Icon(
              Icons.mic,
              size: 18,
              color: state.isTalkActive
                  ? const Color(0xFFF2B33D)
                  : Colors.white24,
            ),
            const SizedBox(width: 8),
            if (state.isTalkActive)
              const MicLevelBars(
                barCount: 5,
                color: Color(0xFFF2B33D),
                minHeight: 4,
                maxHeight: 16,
                barWidth: 2,
                spacing: 2,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: _handleNewChat,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => context.read<AuthService>().logout(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const VoicePicker(),
              const Expanded(child: ChatOutput()),
              ChatInput(
                onSend: _sendMessage,
                onTalkStart: _handleTalkStart,
                onTalkEnd: _handleTalkEnd,
              ),
            ],
          ),
          if (showPtt)
            Positioned(
              left: 0,
              right: 0,
              bottom: 210,
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
