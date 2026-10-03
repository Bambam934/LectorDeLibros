# Créditos de los sonidos ambientales

Los presets de ruido (lluvia, chimenea, oleaje, ruido rosa y ruido blanco) se
generan en el dispositivo y no tienen autoría externa: ver
`lib/features/reader/data/audio/ambient_noise_synth.dart`.

Las grabaciones de este directorio sí proceden de terceros. Ambas están en
**dominio público**, se descargaron de Wikimedia Commons el 2026-08-11 y se
usan en su transcodificación MP3 porque iOS y macOS no reproducen Ogg Vorbis
de forma nativa.

| Archivo | Preset | Original | Autor | Licencia |
|---|---|---|---|---|
| `cafe_ambience.mp3` | Cafetería | [Restaurant ambience.ogg](https://commons.wikimedia.org/wiki/File:Restaurant_ambience.ogg) | stephan (vía pdsounds.org) | Dominio público |
| `forest_birds.mp3` | Bosque | [Birdsong mild sunny day.ogg](https://commons.wikimedia.org/wiki/File:Birdsong_mild_sunny_day.ogg) | stephan (vía pdsounds.org) | Dominio público |

Ninguna de las dos exige atribución legalmente; se acredita al autor por
cortesía, tal y como pide la página de origen.

## Al añadir un sonido nuevo

1. Comprueba que la licencia permite uso comercial sin condiciones (CC0 o
   dominio público). Evita CC BY-SA: obligaría a relicenciar.
2. Conviértelo a MP3 o AAC. **No uses Ogg Vorbis**: no suena en iOS ni macOS.
3. Busca bucles largos. Estos duran 76 s y 37 s, y la repetición se nota si
   prestas atención.
4. Anótalo en esta tabla y declara el asset en `pubspec.yaml`.
