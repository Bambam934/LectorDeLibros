# Construcción: importación sin cargar de más y APK de release solo ARM (2026-10-22)

Para: Antigravity (constructor). De: Claude (diseño y entrega).

El encargo completo, con el contexto verificado, los puntos P1-P2, las restricciones C1-C6, los criterios CA-1…CA-7, las pruebas y el alcance, está en **`docs/prompts/IMPORTACION_2026-10-22.md`**. Léelo entero antes de tocar nada. Este archivo solo fija cómo trabajar.

## Qué haces

1. Comprueba que estás en `desarrollo` con el árbol limpio. Solo puede aparecer este archivo sin rastrear; si hay algo más, para y repórtalo.
2. Crea la rama: `git switch -c encargo/importacion-2026-10-22 --track desarrollo`.
3. Implementa P1 y después P2, con un commit por punto, cada uno después de que pasen sus pruebas.
4. Ejecuta todas las pruebas de la sección «Pruebas» del encargo, builds incluidos, y anota el resultado real: número de tests, salida de `flutter analyze`, ABIs y tamaño de cada APK.
5. Escribe el reporte (formato abajo) en `docs/prompts/IMPORTACION_2026-10-22_CONSTRUCCION.reporte.md`. **No lo commitees.**

## Qué no haces

- Tocar archivos fuera de la lista «sí». Si crees que hace falta otro, no lo toques y anótalo en «Dudas».
- Hacer push, usar `--force`, `--no-verify` o `--amend` sobre commits ajenos, o cambiar de rama base.
- Firmar los commits como IA o añadir `Co-Authored-By`.
- Commitear este archivo o el reporte.
- Abrir, leer o copiar `.env*`, `android/key.properties` o `*.jks`. El build los usa solo, y eso está permitido.
- Cambiar `pubspec.yaml`, `pubspec.lock` o las versiones de los paquetes.
- Usar `--split-per-abi`.

## Comandos permitidos

- `git`: `status`, `switch`, `add <ruta>`, `commit -F`, `log`, `diff` y `show`.
- Desde `lectorsync/`:
  - `flutter analyze`;
  - `flutter test`; puedes usar `flutter test <ruta>` para iterar, pero al final pasa la suite completa;
  - `flutter build apk --release` y `flutter build apk --debug`;
  - el comando de PowerShell del encargo para listar las ABIs del APK.

## Formato del reporte

```markdown
# Reporte: IMPORTACION_2026-10-22

**Constructor: Antigravity**

## Commits
- <hash corto> <mensaje> — P<n>

## Criterios de aceptación
- CA-1: CUMPLE / NO CUMPLE — evidencia (test o comando y archivo:línea)
- … hasta CA-7

## Pruebas
- flutter analyze: <limpio / avisos>
- flutter test: <N pasan / M fallan>
- APK release: <ABIs> · <tamaño en MiB>
- APK debug: <ABIs> · <tamaño en MiB>
- Comprobaciones con el buscador: <resultado de cada una>

## Archivos tocados
- <ruta> (lista completa; debe coincidir con `git diff --stat desarrollo..HEAD`)

## Afirmaciones retiradas
- <lo que no pudiste comprobar y por eso no afirmas>

## Dudas
- <lo que dejaste sin hacer o decidiste por tu cuenta, y por qué>
```

Cada afirmación del reporte necesita una fuente: `archivo:línea`, un test o la salida de un comando. Lo que no puedas comprobar va en «Afirmaciones retiradas», no en los CA.
