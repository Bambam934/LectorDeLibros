/// Búsquedas sobre listas ya ordenadas de forma no decreciente.
library;

/// Índice del **último** elemento de [items] cuya clave es menor o igual que
/// [value], o `-1` si no hay ninguno (lista vacía, o todas las claves
/// mayores).
///
/// Es el patrón "¿en qué tramo cae esta posición?", y estaba copiado palabra
/// por palabra en tres sitios del lector:
///
/// - offset de palabra → párrafo que la contiene (seguidor de voz),
/// - offset de carácter → palabra que el motor está diciendo (TTS de
///   dispositivo),
/// - milisegundo de reproducción → palabra (TTS de servidor).
///
/// Cada copia resolvía el caso "no hay ninguno" a su manera, así que aquí se
/// devuelve `-1` de forma explícita y es el llamante quien decide qué
/// significa eso en su contexto.
int lastIndexAtOrBefore<T>(
  List<T> items,
  int value, {
  required int Function(T item) keyOf,
}) {
  var lo = 0;
  var hi = items.length - 1;
  var result = -1;

  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (keyOf(items[mid]) <= value) {
      result = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }

  return result;
}

/// [lastIndexAtOrBefore] para el caso más común: una lista de offsets.
int lastOffsetAtOrBefore(List<int> offsets, int value) =>
    lastIndexAtOrBefore<int>(offsets, value, keyOf: (offset) => offset);
