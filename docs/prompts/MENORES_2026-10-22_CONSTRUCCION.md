# Construcción: menores de importación y decodificación (2026-10-22)

Para: Antigravity (constructor). De: Claude (diseño y entrega).

El encargo completo, con el contexto verificado, los puntos P1-P3, las restricciones C1-C5, los criterios CA-1…CA-6, las pruebas y el alcance, está en **`docs/prompts/MENORES_2026-10-22.md`**. Léelo entero antes de tocar nada. Este archivo solo fija cómo trabajar.

## Qué haces

1. Comprueba que estás en `desarrollo` con el árbol limpio (solo puede aparecer este archivo sin rastrear). Si hay algo más, para y repórtalo.
2. Crea la rama: `git switch -c encargo/menores-2026-10-22 --track desarrollo`.
3. Implementa P1, P2 y P3 en ese orden, con un commit por punto, después de que pasen sus pruebas.
4. Ejecuta todas las pruebas de la sección «Pruebas» del encargo y guarda el resultado real: el número de tests, los que fallan y la salida de `flutter analyze`.
5. Escribe el reporte (formato abajo) en `docs/prompts/MENORES_2026-10-22_CONSTRUCCION.reporte.md`. **No lo commitees.**

## Qué no haces

- No tocas archivos fuera de la lista «sí» del encargo. Si crees que hace falta otro, no lo toques: anótalo en «Dudas».
- No haces push, no usas `--force`, `--no-verify` ni `--amend` sobre commits ajenos, y no cambias de rama base.
- No firmas los commits como IA ni añades `Co-Authored-By`.
- No commiteas este archivo ni el reporte.
- No lees ni copias `.env`, `.env.local`, `android/key.properties` ni `*.jks`.
- No instalas dependencias nuevas. La única operación de npm permitida es `npm uninstall @types/adm-zip` (P2), además de `npm test` y `npm run typecheck`. No ejecutes `npm audit fix`: poda las devDependencies.

## Comandos permitidos

- `git`: `status`, `switch`, `add <ruta>`, `commit -F`, `log`, `diff` y `show`.
- Desde `backend/`: `npm test`, `npm run typecheck` y `npm uninstall @types/adm-zip`.
- Desde `lectorsync/`: `flutter analyze` y `flutter test` (puede ser `flutter test <ruta>` para iterar, pero al final la suite completa).

## Formato del reporte

```markdown
# Reporte: MENORES_2026-10-22

## Commits
- <hash corto> <mensaje> — P<n>

## Criterios de aceptación
- CA-1: CUMPLE / NO CUMPLE — evidencia (test y archivo:línea)
- … hasta CA-6

## Pruebas
- npm test: <N pasan / M fallan>
- npm run typecheck: <limpio / errores>
- flutter analyze: <limpio / avisos>
- flutter test: <N pasan / M fallan>
- Comprobaciones con el buscador: <resultado de cada una>

## Archivos tocados
- <ruta> (lista completa, que tiene que coincidir con `git diff --stat desarrollo..HEAD`)

## Afirmaciones retiradas
- <lo que no pudiste comprobar y por eso no afirmas>

## Dudas
- <lo que dejaste sin hacer o decidiste por tu cuenta, y por qué>
```

Cada afirmación del reporte necesita una fuente (`archivo:línea`, un test o la salida de un comando). Lo que no puedas comprobar va en «Afirmaciones retiradas», no en los CA.
