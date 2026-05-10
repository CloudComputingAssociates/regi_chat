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
import '../widgets/ptt_button.dart';
import '../widgets/voice_picker.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // POC kill switch: when true, opens a parallel getUserMedia stream to
  // drive real audio-reactive bars. Suspect this conflicts with
  // webkitSpeechRecognition on Chrome — recognition gets a silent stream
  // from the same mic. Set to false to fall back to self-animating bars
  // and let speech_to_text have exclusive mic ownership.
  static const _useMicLevelMeter = false;

  final ChatService _chat = ChatService();
  final WebSpeechService _speech = WebSpeechService();
  final TtsService _tts = TtsService();
  final MicLevelService _micLevel = MicLevelService();
  StreamSubscription<String>? _speechSub;
  StreamSubscription<String>? _speechErrSub;
  StreamSubscription<String>? _micErrSub;

  @override
  void initState() {
    super.initState();
    _speech.initialize();
    // POC: surface every audio-path failure as a chat line so we can debug
    // STT / mic-level issues from the live deploy without DevTools.
    _speechErrSub = _speech.errors.listen((msg) => _logDebug('[stt err] $msg'));
    _speech.statuses.listen((s) => _logDebug('[stt] $s'));
    _micErrSub = _micLevel.errors.listen((msg) => _logDebug('[mic] $msg'));
    // Fire-and-forget voice fetch on first render. Failure is silent — the
    // picker just won't appear, and TTS falls back to the server's default.
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
        content: '⚠️ Not authenticated. Please sign in again.',
        role: MessageRole.assistant,
      ));
      return;
    }

    final wasVoiceMode = state.mode == InputMode.voice;
    final stream = state.startAssistantStream();
    String? lastSessionStatus;
    try {
      await for (final chunk in _chat.streamChat(
        message: text,
        sessionId: state.sessionId,
        jwt: jwt,
      )) {
        // Capture sessionId so subsequent turns resume the same conversation.
        // The server emits it on the first event of a new session and on
        // status events thereafter; setSessionId is a no-op if unchanged.
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

    // If the server told us the session is no longer ACTIVE (timed out, hit
    // the context cap, or was closed), drop the sessionId so the next turn
    // starts a fresh conversation. Surface a small log line so the user
    // knows why memory just reset.
    if (lastSessionStatus != null && lastSessionStatus != 'ACTIVE') {
      state.setSessionId(null);
      if (mounted) {
        state.addMessage(TextMessage(
          content: '[session $lastSessionStatus — starting new conversation]',
          role: MessageRole.assistant,
        ));
      }
    }

    // Speak the assistant reply only when the user is in voice mode.
    // In text mode they're reading; speaking would be intrusive. Fire-and-
    // forget — we don't block _sendMessage on TTS so the user can keep
    // interacting while audio plays. POC: TTS failures are surfaced into
    // the chat output as a visible log line.
    if (wasVoiceMode && stream.content.trim().isNotEmpty) {
      final replyText = stream.content;
      final voiceId = state.selectedVoice?.id;
      unawaited(() async {
        final freshJwt = await auth.getAccessToken() ?? jwt;
        try {
          await _tts.speak(replyText, jwt: freshJwt, voice: voiceId);
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
    if (state.messages.isEmpty && state.sessionId == null) {
      return; // already empty — nothing to clear
    }
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

    // Clear local UI immediately — instant feedback, no waiting on the network.
    context.read<ChatState>().clearChat();

    // Fire-and-forget the server-side close so Status flips to CLOSED.
    // Best-effort: if DELETE fails the session will idle-timeout on its own.
    if (priorSessionId != null && priorSessionId.isNotEmpty) {
      unawaited(() async {
        final jwt = await auth.getAccessToken();
        if (jwt == null) return;
        await _chat.closeSession(sessionId: priorSessionId, jwt: jwt);
      }());
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

  StreamSubscription<double>? _micLevelDebugSub;

  Future<void> _handleTalkStart() async {
    final state = context.read<ChatState>();
    if (state.isPromptMeOn) return;
    state.setTalkActive(true);
    state.setCurrentInput('');

    // Start the audio level sampler in parallel with STT, only if the
    // kill switch above is on. We suspect it starves Web Speech of audio.
    if (_useMicLevelMeter) {
      unawaited(_micLevel.start().then((ok) {
        if (!mounted) return;
        _logDebug('[mic] start ok=$ok');
        if (ok) {
          _micLevelDebugSub?.cancel();
          var peak = 0.0;
          var samples = 0;
          Timer? heartbeat;
          _micLevelDebugSub = _micLevel.levels.listen((v) {
            if (v > peak) peak = v;
            samples++;
          });
          heartbeat = Timer.periodic(const Duration(milliseconds: 500), (t) {
            if (!mounted || _micLevelDebugSub == null) {
              t.cancel();
              return;
            }
            _logDebug(
                '[mic] peak=${peak.toStringAsFixed(3)} samples=$samples');
            peak = 0.0;
            samples = 0;
          });
          _micLevelHeartbeat = heartbeat;
        }
      }));
    } else {
      _logDebug('[mic] meter disabled — STT-only mode');
    }

    final ok = await _speech.initialize();
    _logDebug('[stt] initialize ok=$ok available=${_speech.isAvailable}');
    if (!ok) return;

    _speechSub?.cancel();
    var transcriptCount = 0;
    _speechSub = _speech.listen().listen((transcript) {
      if (!mounted) return;
      transcriptCount++;
      // Log first event and every 5th after, with a short snippet.
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

  Timer? _micLevelHeartbeat;

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
                onPromptMe: _handlePromptMe,
                onTalkStart: _handleTalkStart,
                onTalkEnd: _handleTalkEnd,
                micLevels: _useMicLevelMeter ? _micLevel.levels : null,
              ),
            ],
          ),
          if (showPtt)
            Positioned(
              left: 0,
              right: 0,
              // Bar is now two rows: ~56dp controls + 6dp gap + ~56dp input
              // = ~118dp + ~24dp safe-area + ~52dp gap above = ~210dp.
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
