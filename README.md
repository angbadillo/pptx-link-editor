# PPTX Link Editor

> 🇬🇧 **Embed a chart's data directly into a PowerPoint file on macOS** — making the
> presentation self-contained instead of depending on an external Excel. This is a feature
> available in **Office for Windows but missing on the Mac**, where PowerPoint can only keep
> charts *linked* to an external workbook. The app also lets you repair or redirect those
> external links without corrupting the `.pptx`.
>
> 🇪🇸 **Incrustar los datos de un gráfico directamente en un archivo de PowerPoint en macOS**
> — dejando la presentación autocontenida en lugar de depender de un Excel externo. Es una
> función disponible en **Office para Windows pero ausente en Mac**, donde PowerPoint solo
> puede mantener los gráficos *vinculados* a un libro externo. La app también permite reparar
> o redirigir esos enlaces externos sin estropear el `.pptx`.

**🌐 Language / Idioma:** [English](#english) · [Español](#español)

---

## English

Native macOS (SwiftUI) app to **edit the external data paths** of a `.pptx` file
(charts pointing to an `.xlsx` at another path, linked OLE objects, hyperlinks…)
**without corrupting the file**.

### What it does

1. **Detects** every external path in the `.pptx` (relationships with
   `TargetMode="External"` in any `*.rels` part: charts, OLE objects, linked workbooks…).
2. Lets you **edit them one by one** in their own field.
3. Offers **find & replace** across all paths at once (handy when a whole base folder
   was moved).
4. **Embeds a linked chart's data**: turns it self-contained (no longer depends on the
   external Excel). See below.
5. **Saves a copy** of the `.pptx` with the changes.

### Embedding a chart's data

On macOS, PowerPoint doesn't offer converting a chart linked to an external Excel into one
with embedded data. This app can, at the file-format level.

Every chart carries its data **cached** inside `chartN.xml` (the categories, series and
values it shows). When you click **"Embed data"** on a chart row, the app:

1. Reads that cached data and the cells it maps to (`<c:f>`).
2. Generates a minimal `.xlsx` (~2 KB) with that data.
3. Puts it inside the `.pptx` (`ppt/embeddings/`) and switches the relationship from
   *external* to *internal*.

Result: the `.pptx` becomes **self-contained**, the chart is still editable ("Edit Data"),
and the dependency on the external file disappears (including the OneDrive problem).

> Only the values the chart shows (the cached ones) are embedded, not the full source
> Excel: it's tiny and doesn't bloat the `.pptx`. Hidden columns or formulas from the
> original Excel are not recovered.

### Why it doesn't corrupt the file

A `.pptx` is a ZIP of XML parts. Instead of repackaging with the system `zip` (which
recompresses and reorders everything), this app implements its own ZIP reader/writer:

- Untouched parts are rewritten **byte-for-byte** from the original ZIP.
- Only the edited `.rels` is recompressed (raw DEFLATE via Apple's `Compression`
  framework + a built-in CRC-32).
- Editing the `Target` attribute is **surgical**: only that value is replaced, leaving the
  rest of the XML intact (namespaces, attributes, escaping).

Verified: after editing, the only content that changes is the corresponding `.rels`; the
rest of the package is identical, the ZIP passes `unzip -t` and the file opens with no errors.

### Build and run

```bash
./build_app.sh                 # builds universal (Intel + Apple Silicon),
                               # creates the .app bundle and a .zip to distribute
open "PPTX Link Editor.app"
```

Requirements to *build*: macOS 13+ and Swift 6 (Xcode Command Line Tools).

### Distributing to other machines

`build_app.sh` produces **`PPTX Link Editor.zip`**, self-contained and universal
(arm64 + x86_64). It only depends on system frameworks, so it runs on any **macOS 13 or
later** without installing anything.

On the target machine:

1. Unzip and move the app to `/Applications` (or wherever you want).
2. The first time, macOS will block it because it's not signed with an Apple certificate
   (it's *ad-hoc* signed). To open it:
   - **Right-click → "Open" → "Open"** (only needed the first time), or
   - in Terminal: `xattr -dr com.apple.quarantine "/path/to/PPTX Link Editor.app"`

> To avoid that prompt entirely you'd need to sign and notarize it with an Apple Developer
> account (paid); not necessary for internal use.

### CLI (optional, for automation/testing)

```bash
swift build --product pptxcli
.build/debug/pptxcli list   presentation.pptx
.build/debug/pptxcli replace presentation.pptx 'C:\Users\old' '/Users/me/data' out.pptx
.build/debug/pptxcli embed  presentation.pptx out.pptx        # embed all linked charts
```

### Project layout

```
Sources/
  PptxKit/                    reusable core
    ZipArchive.swift          faithful ZIP reader/writer + DEFLATE
    CRC32.swift               ZIP CRC-32 checksum
    RelsParser.swift          read and surgically edit .rels files
    ChartDataExtractor.swift  extract cached data from chartN.xml
    XlsxBuilder.swift         build a minimal .xlsx to embed
    PptxDocument.swift        link detection, saving and embedding
  pptxcli/                    command-line tool (testing)
  PPTXLinkEditor/             SwiftUI app (App, AppModel, ContentView)
build_app.sh                  packages the double-clickable .app
make_fixture.py               generates a test .pptx with external links
```

### Known limitations

- No ZIP64 support (`.pptx` > 4 GB), uncommon in presentations.
- The app is *ad-hoc* signed (no developer certificate); to distribute it widely you'd
  need to sign and notarize it.

---

## Español

Aplicación nativa de macOS (SwiftUI) para **editar las rutas de datos externas** de un
archivo `.pptx` (gráficos que apuntan a `.xlsx` en otra ruta, objetos OLE vinculados,
hipervínculos…) **sin estropear el archivo**.

### Qué hace

1. **Detecta** todas las rutas externas del `.pptx` (relaciones con `TargetMode="External"`
   en cualquier fichero `*.rels` del paquete: gráficos, objetos OLE, libros vinculados…).
2. Permite **editarlas una por una** en su propio campo.
3. Ofrece **buscar y reemplazar** sobre todas las rutas a la vez (útil cuando una carpeta
   base entera se movió de sitio).
4. **Incrusta los datos de un gráfico** vinculado: lo convierte en autocontenido (deja de
   depender del Excel externo). Ver más abajo.
5. **Guarda una copia** del `.pptx` con los cambios.

### Incrustar los datos de un gráfico

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

### Por qué no corrompe el archivo

Un `.pptx` es un ZIP de piezas XML. En lugar de re-empaquetar con `zip` del sistema
(que recomprime y reordena todo), esta app implementa su propio lector/escritor ZIP:

- Las piezas que **no** se tocan se reescriben **byte a byte** desde el ZIP original.
- Solo se vuelve a comprimir el `.rels` editado (DEFLATE crudo vía framework `Compression`
  de Apple + CRC-32 propio).
- La edición del atributo `Target` es **quirúrgica**: se sustituye solo ese valor dejando
  intacto el resto del XML (namespaces, atributos, escapado).

Verificado: tras editar, el único contenido que cambia es el `.rels` correspondiente;
el resto del paquete queda idéntico, el ZIP pasa `unzip -t` y el archivo abre sin errores.

### Compilar y ejecutar

```bash
./build_app.sh                 # compila universal (Intel + Apple Silicon),
                               # crea el bundle .app y un .zip para distribuir
open "PPTX Link Editor.app"
```

Requisitos para *compilar*: macOS 13+ y Swift 6 (Command Line Tools de Xcode).

### Distribuir a otros equipos

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

### CLI (opcional, para automatizar/probar)

```bash
swift build --product pptxcli
.build/debug/pptxcli list   presentacion.pptx
.build/debug/pptxcli replace presentacion.pptx 'C:\Users\old' '/Users/yo/datos' salida.pptx
.build/debug/pptxcli embed  presentacion.pptx salida.pptx     # incrusta todos los gráficos
```

### Estructura

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

### Limitaciones conocidas

- No soporta archivos ZIP64 (`.pptx` > 4 GB), poco habitual en presentaciones.
- La app está firmada *ad-hoc* (sin certificado de desarrollador); para distribuirla a
  otros equipos habría que firmarla y notarizarla.
