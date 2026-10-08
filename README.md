# LiveRestore 1.1 — Restauración por lotes

App nativa iOS 16+ para importar parejas Live Photo originales desde Archivos (incluidos SMB e iCloud) a Fotos. Usa `.photo` y `.pairedVideo`, sin recomprimir los archivos. La versión 1.0 fue probada por el usuario en su iPhone: la foto restaurada volvió a funcionar como Live Photo. La actualización 1.1 está pendiente de compilar y probar en dispositivo.

## Actualizar desde la versión anterior

Sube estos tres archivos al repositorio existente, reemplazando los correspondientes:
- `LiveRestore/ContentView.swift`
- `LiveRestore/LivePhotoService.swift`
- `project.yml`

Añade también `LiveRestore/BatchService.swift`. Conserva el workflow, `FilePicker.swift` y `LiveRestoreApp.swift` del repositorio. GitHub Actions compilará al hacer commit en `main`. Descarga el artefacto `LiveRestore-unsigned-ipa`, extrae la IPA e instálala con Sideloadly utilizando el mismo Apple ID y bundle ID que antes.

## Uso

1. Abre Elegir imágenes y MOV y selecciona todos los originales que quieras restaurar. Por ejemplo, 10 HEIC y sus 10 MOV.
2. Espera a que termine la lectura y se indique cuántas parejas se han encontrado.
3. Revisa los avisos de archivos omitidos. Se muestra la vista previa de la primera pareja.
4. Pulsa Restaurar N Live Photos. Se valida cada pareja con iOS y se importa de forma secuencial. Mantén la app en primer plano.
5. Consulta el resumen y la lista de resultados. Un error en una pareja no bloquea las demás.
6. Puedes detener después de la foto actual y reanudar, o reintentar las fallidas. Las guardadas se excluyen del siguiente intento dentro de la misma selección.

Para el NAS: Archivos → Explorar → ⋯ → Conectarse al servidor → dirección SMB y credenciales. Selecciona los archivos, no una carpeta. El emparejamiento se hace usando el identificador Live Photo de los metadatos, no el nombre ni el orden de selección. Se rechazan identificadores repetidos ambiguos, parejas incompletas e imágenes o vídeos sin identificador original.

## Compilar

El workflow `.github/workflows/build-ipa.yml` incluido genera una IPA sin firmar en un runner macOS. El contenido de esta carpeta debe estar en la raíz del repositorio. Actions → Build iPhone IPA → Run workflow. Tras el resultado verde, descarga el artefacto y usa Sideloadly para firmar e instalar.

En un Mac con Xcode:

```sh
brew install xcodegen
xcodegen generate
open LiveRestore.xcodeproj
```

Selecciona tu equipo de firma y ejecuta en el iPhone. La app no necesita ordenador, Python ni companion durante el uso.

## Límites

- Solo restaura parejas originales con metadatos intactos; no reconstruye identificadores perdidos.
- Se copian todos los archivos seleccionados al almacenamiento temporal antes de importar: hace falta espacio libre para el lote. Las copias temporales de la selección se borran al seleccionar un nuevo lote o cuando todas sus parejas quedan guardadas. Los originales del NAS no se modifican.
- Se mantiene solo una Live Photo decodificada cada vez para limitar el uso de memoria.
- El estado de guardado se mantiene durante la sesión: volver a seleccionar los mismos originales o reiniciar la app puede crear duplicados. No hay deduplicación global contra Fotos ni recuperación persistente tras un cierre.
- No se garantiza recuperar fechas, localización, álbumes ni ediciones de la fototeca original.
- La versión 1.1 se ha preparado en Linux sin SDK iOS; no se incluye IPA precompilada. La compilación y la prueba por lotes en iPhone siguen pendientes.

Pruebas de aceptación: una pareja, varias parejas en orden mezclado, nombres diferentes con identificador coincidente, pareja incompleta, duplicados ambiguos, permiso denegado, una pareja corrupta entre parejas válidas, detener/reanudar y reintentar sin duplicar guardadas.
