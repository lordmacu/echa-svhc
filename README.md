# ECHA — consulta SVHC + Annex XIV por CAS

App de escritorio (**macOS** y **Windows**) que consulta, por número **CAS**, la
existencia de una sustancia en **tres listas de ECHA**:

1. **Candidate List (SVHC)** — [`candidate-list-table`](https://www.echa.europa.eu/candidate-list-table)
2. **Authorisation List (REACH Annex XIV) — nueva** — [`chem.echa.europa.eu/.../authorisationList`](https://chem.echa.europa.eu/obligation-lists/authorisationList) (API JSON)
3. **Authorisation List (REACH Annex XIV) — legado** — [`authorisation-list`](https://www.echa.europa.eu/authorisation-list)

Pega uno o varios CAS (los detecta automáticamente y los convierte en *chips*),
pulsa **Consultar** y la app revisa **uno por uno** cada sustancia y muestra una
**tabla con 3 columnas** (✓/✗ por fuente). Cada fila se expande para ver los
detalles de cada lista: nombre, EC, fecha de inclusión / motivo (Candidate) y
Entry No., Latest application date, Sunset date (Annex XIV).

![estado](https://github.com/lordmacu/echa-svhc/actions/workflows/build.yml/badge.svg)

## Descargas

| Plataforma | Descarga |
|---|---|
| 🍎 **macOS** | [echa_svhc-macos.dmg](https://github.com/lordmacu/echa-svhc/releases/latest/download/echa_svhc-macos.dmg) |
| 🪟 **Windows** (portable) | [echa_svhc-windows-portable.zip](https://github.com/lordmacu/echa-svhc/releases/latest/download/echa_svhc-windows-portable.zip) |

Los enlaces apuntan siempre al [último release](https://github.com/lordmacu/echa-svhc/releases/latest).
En Windows, descomprime el `.zip` y ejecuta `echa_svhc.exe` (no requiere instalación).

---

## Características

- **3 fuentes por CAS**: Candidate List (SVHC), Annex XIV nuevo (ECHA CHEM) y Annex XIV legado.
- **Tabla con 3 columnas** de indicadores (✓ en lista / ✗ no / ⚠ error); cada fila se expande con el detalle por fuente.
- **Detección automática de formato CAS** (`2–7 dígitos - 2 dígitos - 1 dígito`), incluso pegando texto/prosa que los contenga.
- **Importar desde archivo**: carga un `.csv`, `.txt`, `.xlsx` o `.xls` y extrae automáticamente todos los CAS (de cualquier columna/hoja).
- Entrada por **chips**: agrega, valida el dígito de control y elimina CAS fácilmente.
- **Filtros** (solo Candidate List, como en la web): Reason for inclusion (Art. 57) y rango de fecha de inclusión.
- Consulta **secuencial** (uno por uno) con barra de progreso.

## Cómo funciona

Cada CAS se consulta contra tres fuentes (ver [`test.md`](test.md) para el reverse-engineering completo):

1. **Candidate List** y **Annex XIV legado** (portal Liferay): la búsqueda real es un
   **render GET** (`p_p_lifecycle=0`) con criterios *namespaced* + `_doSearch=true`;
   la verdad está en el campo oculto `_total` (0 = no listado). Solo requiere cookies.
2. **Annex XIV nuevo** (ECHA CHEM): API JSON
   `api-obligation-list/v1/authorisationList?searchText=<cas>`.

Por qué **escritorio** y no web: el navegador bloquearía estas peticiones por
**CORS** (ECHA solo permite su propio dominio). Una app nativa hace peticiones
HTTP crudas (como `curl`), sin esa restricción.

## Desarrollo

```bash
flutter pub get
flutter run -d macos        # o -d windows
```

Pruebas:

```bash
flutter test
```

Prueba de humo contra ECHA real (sin GUI):

```bash
dart run tool/smoke.dart
```

## Builds (CI)

GitHub Actions ([`.github/workflows/build.yml`](.github/workflows/build.yml))
compila en cada push a `main` y publica como *artifacts*:

- **macOS** → `echa_svhc-macos.dmg`
- **Windows** → `echa_svhc-windows-portable.zip` (ejecutable portable + DLLs)

Al crear un **tag** `vX.Y.Z` los binarios se adjuntan a un **GitHub Release**:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Nota

El portal usado (`www.echa.europa.eu/candidate-list-table`) es **legado**:
ECHA lo mantiene hasta **julio 2026**. La versión nueva es el SPA
`https://chem.echa.europa.eu/obligation-lists/candidateList`.
