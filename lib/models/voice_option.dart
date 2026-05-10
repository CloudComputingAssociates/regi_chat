/// One entry from `GET /api/tts/voices`. Matches regi-api's
/// `external_apis.VoiceOption` JSON shape.
class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.displayName,
    required this.gender,
  });

  final String id;
  final String displayName;
  final String gender;

  factory VoiceOption.fromJson(Map<String, dynamic> json) => VoiceOption(
        id: json['id'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is VoiceOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
