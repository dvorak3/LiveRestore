# LiveRestore

App nativa iPhone/iPad (iOS 16+) para restaurar una pareja Live Photo original HEIC/JPEG + MOV desde Archivos a Fotos. No necesita Python, iTunes ni un programa de escritorio para importar. El ordenador solo interviene al compilar/instalar la app.

## Qué hace

1. Seleccionas exactamente dos archivos desde Archivos, incluidos proveedores SMB o iCloud.
2. Copia los originales al almacenamiento temporal local sin recomprimir.
3. Comprueba el identificador Apple de la imagen (MakerApple, clave 17) y el `com.apple.quicktime.content.identifier` del MOV.
4. Pide a iOS validar/cargar la Live Photo y muestra una vista previa interactiva.
5. El botón Guardar crea un único recurso en Fotos con `PHAssetCreationRequest`, `.photo` y `.pairedVideo`.

Solo pide permiso para **añadir** a Fotos. Los archivos seleccionados permanecen intactos. El botón queda deshabilitado tras guardar para evitar duplicados accidentales en esa sesión. Si seleccionas la misma pareja otra vez, puedes crear otra copia.

Esta versión restaura originales con metadatos de emparejamiento intactos. No repara metadatos rotos, no convierte un vídeo cualquiera, no importa lotes y no es todavía una integración dentro de Pho. No se accede directamente a Samba: se utiliza el proveedor SMB de Archivos.

## Instalar sin Mac propio: GitHub Actions + Sideloadly

1. Crea un repositorio GitHub y sube **el contenido de esta carpeta**, incluyendo `.github/workflows/build-ipa.yml`. `project.yml` debe quedar en la raíz del repositorio.
2. Abre Actions → Build iPhone IPA → Run workflow. Si GitHub pide activar Actions, actívalo.
3. Cuando finalice correctamente, descarga el artefacto `LiveRestore-unsigned-ipa` y descomprime el ZIP.
4. Arrastra `LiveRestore-unsigned.ipa` a Sideloadly y fírmala/instálala con tu Apple ID como hiciste con PhotoBridge.
5. Abre LiveRestore en el iPhone. No hay ningún bundle ID de companion que configurar ni conexión USB durante el uso.

El flujo de Actions usa un runner macOS y Xcode. Su disponibilidad, cuota y posibles costes dependen de tu cuenta de GitHub. La IPA descargada **no está firmada**: Sideloadly debe firmarla antes de instalar. La duración de la firma depende del tipo de cuenta Apple.

## Compilar en un Mac

Necesitas Xcode con SDK iOS y XcodeGen:

```sh
brew install xcodegen
xcodegen generate
open LiveRestore.xcodeproj
```

En Xcode, selecciona tu equipo de firma en Signing & Capabilities, cambia el bundle ID si fuera necesario, conecta el iPhone y pulsa Run.

## Usar desde el NAS

1. Si estás fuera de casa, conecta Tailscale en el iPhone y comprueba el acceso al NAS.
2. En Archivos → Explorar → menú ⋯ → Conectarse al servidor, introduce `smb://100.111.164.38` (o la dirección actual de tu NAS) y tus credenciales Samba.
3. Abre LiveRestore → Elegir HEIC y MOV → navega a la carpeta compartida y selecciona ambos originales. Si el proveedor no deja seleccionar varios, copia ambos a una carpeta en En mi iPhone y selecciónalos allí.
4. Mantén pulsada la vista previa: debe reproducir el movimiento.
5. Pulsa Guardar Live Photo en Fotos y acepta el permiso.
6. En Fotos, busca las fotos añadidas recientemente, comprueba la etiqueta LIVE y mantén pulsada la foto.

## Validación y límites de esta entrega

El proyecto se ha preparado en Linux, sin Xcode ni SDK iOS. **No se ha compilado ni probado en un iPhone en esta entrega**, y no se incluye una IPA precompilada. El workflow permite realizar la compilación en macOS; una ejecución correcta es necesaria antes de instalar.

Prueba de aceptación pendiente: usar una pareja original conocida (por ejemplo IMG_8015), reproducir la vista previa, guardarla y comprobar que Fotos muestra una única Live Photo con movimiento y audio. Probar también pareja incorrecta, cancelación del selector, permiso denegado y acceso SMB. No se afirma que la fecha de captura, localización, ediciones o pertenencia a álbumes se restauren íntegramente; esta versión conserva los archivos originales y restaura el emparejamiento.

Arquitectura: `LivePair` prepara y gestiona las copias; `LivePhotoService` valida, previsualiza e importa; `RestoreModel` controla el estado; las vistas contienen la interfaz y el selector del sistema.

Documentación Apple:
- https://developer.apple.com/documentation/avfoundation/capturing-and-saving-live-photos
- https://developer.apple.com/documentation/photos/phassetcreationrequest
- https://developer.apple.com/documentation/photos/phlivephoto
