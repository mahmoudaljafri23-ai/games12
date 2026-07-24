import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:agora_token_service/agora_token_service.dart';

const String agoraAppId = '68d87b236efd42d98269a09268214fae';
const String agoraAppCertificate = 'b2686beafbb342bdb2ce0485dde3b9cb';

class VoiceService {
  // Singleton Pattern
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _isJoined = false;

  bool get isJoined => _isJoined;

  static final ValueNotifier<String> statusNotifier = ValueNotifier<String>('غير متصل');

  // ===== Initialize Agora Engine =====
  Future<void> initialize() async {
    if (_isInitialized) return;

    statusNotifier.value = '⏳ طلب صلاحية المايك...';
    try {
      await [Permission.microphone].request();
    } catch (e) {
      debugPrint("Agora: Permission error: $e");
    }

    statusNotifier.value = '⏳ تهيئة محرك الصوت...';

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(const RtcEngineContext(
        appId: agoraAppId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));

      // Enable audio modules and speakerphone
      await _engine!.enableAudio();
      await _engine!.enableLocalAudio(true);
      await _engine!.setDefaultAudioRouteToSpeakerphone(true);
      await _engine!.setEnableSpeakerphone(true);

      // Register Event Handler
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) async {
          debugPrint("Agora: ✅ Successfully joined channel: ${connection.channelId} for account: ${connection.localUid}");
          statusNotifier.value = '✅ متصل بالصوت بنجاح!';
          try {
            await _engine?.setDefaultAudioRouteToSpeakerphone(true);
            await _engine?.setEnableSpeakerphone(true);
            await _engine?.muteLocalAudioStream(false);
          } catch (_) {}
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint("Agora Error: [$err] $msg");
          statusNotifier.value = '❌ خطأ الصوت: $err';
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) async {
          debugPrint("Agora: Remote user joined: $remoteUid");
          statusNotifier.value = '✅ لاعب آخر انضم للصوت!';
          try {
            await _engine?.setDefaultAudioRouteToSpeakerphone(true);
            await _engine?.setEnableSpeakerphone(true);
          } catch (_) {}
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint("Agora: Remote user left: $remoteUid");
        },
        onAudioRoutingChanged: (int routing) async {
          debugPrint("Agora: Audio routing changed to $routing - forcing loudspeaker");
          try {
            await _engine?.setDefaultAudioRouteToSpeakerphone(true);
            await _engine?.setEnableSpeakerphone(true);
          } catch (_) {}
        },
        onConnectionStateChanged: (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) async {
          debugPrint("Agora connection state: $state reason: $reason");
          if (state == ConnectionStateType.connectionStateConnected) {
            statusNotifier.value = '✅ متصل بالصوت!';
            try {
              await _engine?.setDefaultAudioRouteToSpeakerphone(true);
              await _engine?.setEnableSpeakerphone(true);
            } catch (_) {}
          } else if (state == ConnectionStateType.connectionStateFailed) {
            statusNotifier.value = '❌ فشل الاتصال بالصوت';
          }
        },
      ));

      _isInitialized = true;
      statusNotifier.value = '✅ المحرك جاهز';
    } catch (e) {
      debugPrint("Agora init error: $e");
      statusNotifier.value = '❌ خطأ التهيئة: $e';
    }
  }

  // ===== Join Voice Channel with User Account =====
  Future<void> joinChannel(String roomId, String uid) async {
    if (!_isInitialized) await initialize();
    if (_engine == null) return;
    
    if (_isJoined) {
      try {
        await _engine!.muteLocalAudioStream(false);
        await _engine!.enableLocalAudio(true);
      } catch (_) {}
      return;
    }

    final channelName = 'room_$roomId';
    statusNotifier.value = '⏳ جاري الاتصال بالغرفة الصوتية...';

    // Generate token dynamically using exact Firebase string UID
    final token = RtcTokenBuilder.build(
      appId: agoraAppId,
      appCertificate: agoraAppCertificate,
      channelName: channelName,
      uid: uid, // Use Firebase String UID
      role: RtcRole.publisher,
      expireTimestamp: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400,
    );

    try {
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      await _engine!.joinChannelWithUserAccount(
        token: token,
        channelId: channelName,
        userAccount: uid, // Use Firebase String UID
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

      _isJoined = true;
      _startSpeakerEnforcer();

      // Force mic to stay OPEN for everyone continuously
      Future.delayed(const Duration(milliseconds: 500), () async {
        await forceLoudspeaker();
      });
    } catch (e) {
      debugPrint("Agora joinChannelWithUserAccount error: $e");
      statusNotifier.value = '❌ خطأ الانضمام: $e';
    }
  }

  Timer? _speakerEnforcerTimer;

  Future<void> forceLoudspeaker() async {
    if (_engine == null) return;
    try {
      await _engine!.setDefaultAudioRouteToSpeakerphone(true);
      await _engine!.setEnableSpeakerphone(true);
      await _engine!.muteLocalAudioStream(false);
      await _engine!.enableLocalAudio(true);
    } catch (_) {}
  }

  void _startSpeakerEnforcer() {
    _speakerEnforcerTimer?.cancel();
    _speakerEnforcerTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isJoined) {
        forceLoudspeaker();
      }
    });
  }

  // ===== Leave Voice Channel =====
  Future<void> leaveChannel() async {
    try {
      _speakerEnforcerTimer?.cancel();
      await _engine?.leaveChannel();
      _isJoined = false;
      statusNotifier.value = 'غير متصل';
    } catch (e) {
      debugPrint("Agora error leaving channel: $e");
    }
  }

  // ===== Keep Mic Muted / Unmuted Helper =====
  Future<void> setMuted(bool muted) async {
    if (_engine == null) return;
    try {
      await _engine!.muteLocalAudioStream(muted);
    } catch (_) {}
  }

  // ===== Stub methods for GameScreen (mic stays permanently open) =====
  Future<void> openMicBetween(String roomId, String myUid, List<String> selectedUids) async {}
  Future<void> closeAllMics(String roomId) async {}

  // ===== Release Engine =====
  Future<void> releaseEngine() async {
    try {
      await _engine?.leaveChannel();
      await _engine?.release();
    } catch (_) {}
    _engine = null;
    _isInitialized = false;
    _isJoined = false;
    statusNotifier.value = 'غير متصل';
  }
}
