import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/input_mode.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/mic_level_service.dart';
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
  // POC kill switch: when true, opens a parallel getUserMedia stream to
  // drive real audio-reactive bars. Conflicts with webkitSpeechRecognition
  // on Chrome — recognition gets a silent stream from the same mic.
  static const _useMicLevelMeter = false;

  final ChatService _chat = ChatService();
  final WebSpeechService _speech = WebSpeechService();
  final TtsService _tts = TtsService();
  final MicLevelService _micLevel = MicLevelService();
  StreamSubscription<String>? _speechSub;
  StreamSubscription<String>? _speechErrSub;
  StreamSubscription<String>? _micErrSub;
  StreamSubscription<double>? _micLevelDebugSub;
  Timer? _micLevelHeartbeat;

  // Prepended to the first user message of a new session so the model is
  // primed for short, voice-friendly replies. Subsequent turns inherit.
  static const _conciseDirective =
      'Be concise. Reply in 1-3 sentences unless I ask for more detail. ';

  @override
  void initState() {
    super.initState();
    _speech.initialize();
    _speechErrSub = _speech.errors.listen((msg) => _logDebug('[stt err] $msg'));
    _speech.statuses.listen((s) => _logDebug('[stt] $s'));
    _micErrSub = _micLevel.errors.listen((msg) => _logDebug('[mic] $msg'));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVoices());
  }

  void _logDebug(String content) {
    if (!mounted) return;
    context.read<ChatState>().addMessage(TextMessage(
          content: content,
          role: MessageRole.assistant,
        ));
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
    _speechErrSub?.cancel();
    _micErrSub?.cancel();
    _micLevelDebugSub?.cancel();
    _micLevelHeartbeat?.cancel();
    _speech.stop();
    _speech.dispose();
    _micLevel.dispose();
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

    final isNewSession = state.sessionId == null;
    final messageToSend = isNewSession ? '$_conciseDirective$text' : text;

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

    // Speak the assistant reply when TTS is enabled (independent of input
    // mode). Mute toggle on the chat input bar disables this. Fire-and-
    // forget so synthesis latency doesn't block the next message.
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

    if (_useMicLevelMeter) {
      unawaited(_micLevel.start().then((ok) {
        if (!mounted) return;
        _logDebug('[mic] start ok=$ok');
      }));
    }

    final ok = await _speech.initialize();
    _logDebug('[stt] initialize ok=$ok available=${_speech.isAvailable}');
    if (!ok) return;

    _speechSub?.cancel();
    var transcriptCount = 0;
    _speechSub = _speech.listen().listen((transcript) {
      if (!mounted) return;
      transcriptCount++;
      if (transcriptCount == 1 || transcriptCount % 5 == 0) {
        final snippet = transcript.length > 40
            ? '${transcript.substring(0, 40)}…'
            : transcript;
        _logDebug('[stt] event #$transcriptCount: "$snippet" '
            '(len=${transcript.length})');
      }
      context.read<ChatState>().setCurrentInput(transcript);
    });
  }

  Future<void> _handleTalkEnd() async {
    final state = context.read<ChatState>();
    if (!state.isTalkActive) return;

    await _speech.stop();
    await _speechSub?.cancel();
    _speechSub = null;
    _micLevelHeartbeat?.cancel();
    _micLevelHeartbeat = null;
    await _micLevelDebugSub?.cancel();
    _micLevelDebugSub = null;
    unawaited(_micLevel.stop());

    final transcript = state.currentInput.trim();
    _logDebug('[stt] release: transcript="${transcript.length} chars" '
        'sending=${transcript.isNotEmpty}');
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
        // Title doubles as a status indicator: "RegiMenu" + a mic icon that
        // lights up amber while listening + the audio-level squigglies to
        // its right (only visible during talk).
        title: Row(
          children: [
            const Text('RegiMenu'),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              child: Icon(
                Icons.mic,
                size: 18,
                color: state.isTalkActive
                    ? const Color(0xFFF2B33D)
                    : Colors.white24,
              ),
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
              // Bar is two rows: ~56dp controls + 6dp gap + ~56dp input
              // = ~118dp + ~24dp safe-area + ~52dp gap = ~210dp.
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
