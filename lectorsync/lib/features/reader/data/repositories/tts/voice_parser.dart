List<Map<String, String>> parseVoices(
  dynamic raw,
  String? localePrefix,
) {
  if (raw is! List) return const [];
  final voices = <Map<String, String>>[];
  for (final v in raw) {
    if (v is Map) {
      final m = <String, String>{};
      v.forEach((k, val) {
        if (k is String && val != null) m[k] = val.toString();
      });
      if (m.isNotEmpty) voices.add(m);
    }
  }
  if (localePrefix != null && localePrefix.isNotEmpty) {
    final lower = localePrefix.toLowerCase();
    return voices
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith(lower))
        .toList();
  }
  return voices;
}

/// Si la voz necesita conexión para sintetizar. En Android, flutter_tts lo
/// expone como `network_required` ("1"/"0"): las voces `-network` de Google
/// no suenan sin internet, y elegirlas en modo offline dejaba el lector mudo
/// sin ningún aviso. Las demás plataformas no traen el dato.
bool voiceNeedsNetwork(Map<String, String> voice) =>
    voice['network_required'] == '1';
