# PPTX Link Editor (Editor de enlaces PPTX)

Aplicación nativa de macOS (SwiftUI) para **editar las rutas de datos externas** de un
archivo `.pptx` (gráficos que apuntan a `.xlsx` en otra ruta, objetos OLE vinculados,
hipervínculos…) **sin estropear el archivo**.

## Qué hace

1. **Detecta** todas las rutas externas del `.pptx` (relaciones con `TargetMode="External"`
   en cualquier fichero `*.rels` del paquete: gráficos, objetos OLE, libros vinculados…).
2. Permite **editarlas una por una** en su propio campo.
3. Ofrece **buscar y reemplazar** sobre todas las rutas a la vez (útil cuando una carpeta
   base entera se movió de sitio).
4. **Incrusta los datos de un gráfico** vinculado: lo convierte en autocontenido (deja de
   depender del Excel externo). Ver más abajo.
5. **Guarda una copia** del `.pptx` con los cambios.

## Incrustar los datos de un gráfico

En macOS, PowerPoint no ofrece convertir un gráfico vinculado a un Excel externo en uno con
datos incrustados. Esta app sí puede, a nivel de formato de fichero.

Cada gráfico lleva sus datos **cacheados** dentro de `chartN.xml` (las categorías, series y
valores que muestra). Al pulsar **«Incrustar datos»** en una fila de gráfico, la app:

1. Lee esos datos cacheados y las celdas a las que corresponden (`<c:f>`).
2. Genera un `.xlsx` mínimo (~2 KB) con esos datos.
3. Lo mete dentro del `.pptx` (`ppt/embeddings/`) y cambia la relación de *externa* a
   *interna*.

Resultado: el `.pptx` queda **autocontenido**, el gráfico sigue siendo editable («Editar
datos») y desaparece la dependencia del archivo externo (también el problema de OneDrive).

> Se incrustan los valores que el gráfico muestra (los cacheados), no el Excel de origen
> completo: es minúsculo y no infla el `.pptx`. Si necesitas columnas ocultas o fórmulas del
> Excel original, eso no se recupera.

## Por qué no corrompe el archivo

Un `.pptx` es un ZIP de piezas XML. En lugar de re-empaquetar con `zip` del sistema
(que recomprime y reordena todo), esta app implementa su propio lector/escritor ZIP:

- Las piezas que **no** se tocan se reescriben **byte a byte** desde el ZIP original.
- Solo se vuelve a comprimir el `.rels` editado (DEFLATE crudo vía framework `Compression`
  de Apple + CRC-32 propio).
- La edición del atributo `Target` es **quirúrgica**: se sustituye solo ese valor dejando
  intacto el resto del XML (namespaces, atributos, escapado).

Verificado: tras editar, el único contenido que cambia es el `.rels` correspondiente;
el resto del paquete queda idéntico, el ZIP pasa `unzip -t` y el archivo abre sin errores.

## Compilar y ejecutar

```bash
./build_app.sh                 # compila universal (Intel + Apple Silicon),
                               # crea el bundle .app y un .zip para distribuir
open "PPTX Link Editor.app"
```

Requisitos para *compilar*: macOS 13+ y Swift 6 (Command Line Tools de Xcode).

## Distribuir a otros equipos

`build_app.sh` genera **`PPTX Link Editor.zip`**, autocontenido y universal
(arm64 + x86_64). Solo depende de frameworks del sistema, así que funciona en cualquier
**macOS 13 o superior** sin instalar nada.

En el equipo de destino:

1. Descomprimir el `.zip` y mover la app a `/Aplicaciones` (o donde se quiera).
2. La primera vez macOS la bloqueará por no estar firmada por un certificado de Apple
   (va firmada *ad-hoc*). Para abrirla:
   - **Clic derecho → «Abrir» → «Abrir»** (solo hace falta la primera vez), o
   - en Terminal: `xattr -dr com.apple.quarantine "/ruta/a/PPTX Link Editor.app"`

> Para evitar ese aviso por completo haría falta firmarla y notarizarla con una cuenta de
> Apple Developer (de pago); no es necesario para uso interno.

## CLI (opcional, para automatizar/probar)

```bash
swift build --product pptxcli
.build/debug/pptxcli list   presentacion.pptx
.build/debug/pptxcli replace presentacion.pptx 'C:\Users\old' '/Users/yo/datos' salida.pptx
```

## Estructura

```
Sources/
  PptxKit/                 núcleo reutilizable
    ZipArchive.swift       lector/escritor ZIP con preservación fiel + DEFLATE
    CRC32.swift            checksum CRC-32 del formato ZIP
    RelsParser.swift       lectura y edición quirúrgica de ficheros .rels
    ChartDataExtractor.swift  extrae datos cacheados de chartN.xml
    XlsxBuilder.swift      construye un .xlsx mínimo para incrustar
    PptxDocument.swift     detección de enlaces, guardado e incrustado
  pptxcli/                 herramienta de línea de comandos (pruebas)
  PPTXLinkEditor/          app SwiftUI (App, AppModel, ContentView)
build_app.sh               empaqueta la .app de doble clic
make_fixture.py            genera un .pptx de prueba con enlaces externos
```

## Limitaciones conocidas

- No soporta archivos ZIP64 (`.pptx` > 4 GB), poco habitual en presentaciones.
- La app está firmada *ad-hoc* (sin certificado de desarrollador); para distribuirla a
  otros equipos habría que firmarla y notarizarla.
