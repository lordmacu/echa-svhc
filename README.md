# ECHA SVHC — consulta la Candidate List por CAS

App de escritorio (**macOS** y **Windows**) que consulta la
[Candidate List of substances of very high concern (SVHC)](https://www.echa.europa.eu/candidate-list-table)
de ECHA por número **CAS**.

Pega uno o varios CAS (los detecta automáticamente y los convierte en *chips*),
pulsa **Consultar** y la app revisa **uno por uno** si cada sustancia está o no
en la Candidate List, mostrando nombre, EC number, fecha de inclusión y motivo
(Artículo 57).

![estado](https://github.com/lordmacu/echa-svhc/actions/workflows/build.yml/badge.svg)

---

## Características

- **Detección automática de formato CAS** (`2–7 dígitos - 2 dígitos - 1 dígito`) en texto pegado.
- Entrada por **chips**: agrega, valida el dígito de control y elimina CAS fácilmente.
- Consulta **secuencial** (uno por uno) con barra de progreso.
- Por cada CAS:
  - ✅ **En la lista** — con nombre, EC, fecha de inclusión, motivo (Art. 57) y nº de decisión.
  - ❌ **No está** en la Candidate List.
  - ⚠️ **Error** (red/sesión).

## Cómo funciona

Replica el flujo verificado del buscador de ECHA (un portlet Liferay tras Azure WAF):

1. **GET** a la página base → extrae `p_auth` (token CSRF), `formDate` y cookies de sesión.
2. **POST** a la URL de acción del portlet reusando cookies + `p_auth`.
3. El POST puede devolver un **HTTP 403 engañoso**: el cuerpo trae el HTML real → se parsea el *body*, no el status code.
4. No se siguen redirects (el redirect final sí cae en un 403 real del WAF).

> Detalles completos del reverse-engineering en [`test.md`](test.md).

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
