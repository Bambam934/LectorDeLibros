import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/domain/entities/ambient_sound.dart';

void main() {
  group('AmbientSoundPresets', () {
    test('all presets have unique IDs', () {
      final ids = AmbientSoundPresets.all.map((s) => s.id).toList();
      expect(ids.length, ids.toSet().length);
    });

    test('all presets have non-empty label and source', () {
      for (final sound in AmbientSoundPresets.all) {
        expect(sound.label, isNotEmpty);
        expect(sound.source, isNotEmpty);
      }
    });

    test('byId returns matching preset', () {
      final rain = AmbientSoundPresets.byId('rain');
      expect(rain, isNotNull);
      expect(rain!.label, 'Lluvia');
    });

    test('byId returns null for unknown ID', () {
      expect(AmbientSoundPresets.byId('nonexistent'), isNull);
    });

    test('isAsset is false for HTTP URLs', () {
      for (final sound in AmbientSoundPresets.all) {
        if (sound.source.startsWith('http')) {
          expect(sound.isAsset, isFalse);
        }
      }
    });

    test('isAsset detects asset: prefix', () {
      const assetSound = AmbientSound(
        id: 'test',
        label: 'Test',
        icon: Icons.music_note_rounded,
        source: 'asset:sounds/test.mp3',
      );
      expect(assetSound.isAsset, isTrue);
      expect(assetSound.assetPath, 'sounds/test.mp3');
    });

    test('AmbientSound equality based on id, label, source', () {
      const a = AmbientSound(
        id: 'x',
        label: 'X',
        icon: Icons.music_note_rounded,
        source: 'url-1',
      );
      const b = AmbientSound(
        id: 'x',
        label: 'X',
        icon: Icons.music_note_rounded,
        source: 'url-1',
      );
      expect(a, equals(b));
    });
  });
}
