// This file is loaded only via conditional import on web targets, so the
// dart:html dependency is intentional and safe.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Returns `navigator.userAgent` when running on the web, used to detect
/// browser-specific TTS quirks (e.g. Safari's much lower utterance limit).
String? readBrowserUserAgent() {
  try {
    return html.window.navigator.userAgent;
  } catch (_) {
    return null;
  }
}
