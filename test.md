# ECHA Candidate List (SVHC) — cómo consultarla por CAS

Notas de ingeniería inversa del buscador de la **Candidate List of substances of
very high concern** de ECHA. Caso de prueba: **CAS 110-54-3 (n-hexano)**.

---

## TL;DR

Sí se puede con `curl`. El patrón es **GET a la página base → extraer token + cookies → POST a la acción**:

1. La **página base** (`/web/guest/candidate-list-table`, sin params de acción) **no tiene WAF** y entrega `p_auth`, `formDate` y las cookies de sesión.
2. El POST de búsqueda va a la URL de **acción** del portlet, reusando cookies + `p_auth`.
3. El campo de búsqueda se llama **`_disslists_WAR_disslistsportlet_substance_identifier_field_key`** (NO `searchText`).
4. El POST devuelve **HTTP 403 engañoso** pero el cuerpo trae el HTML real con los resultados → **parsear el body, no filtrar por status code**.

---

## Lo que NO es

- `https://webtools.europa.eu/rest/requests/files?...&ref=aHR0cHM6Ly93d3cuZWNoYS5ldXJvcGEuZXU=`
  → es el servicio de **consentimiento de cookies / analytics (EAMS)** de la Comisión Europea.
  El `ref` en base64 decodifica a `https://www.echa.europa.eu`. Es ruido de carga, da 403 y no contiene nada del químico.

- `https://chem.echa.europa.eu/api-substance/v1/substance?searchText=110-54-3`
  → API limpia (GET, sin WAF, sin token) pero es un **buscador de identidad de sustancia genérico**.
  Devuelve el químico exista o no en la Candidate List; **no** indica pertenencia, motivo ni fecha de inclusión.
  Útil solo para identidad (nombre, EC, CAS, fórmula, SMILES, InChI, Index).

---

## Obstáculos encontrados

| Obstáculo | Detalle |
|---|---|
| **Azure WAF (JS Challenge)** | Salta en la URL de *acción* (`p_p_lifecycle=1`) si entras en frío. La página **base** no lo dispara. |
| **`p_auth`** | Token CSRF de Liferay, **por sesión y caduca**. Hay que leerlo del HTML de la página base. |
| **`formDate`** | Timestamp de sesión, también dinámico. Sale del HTML. |
| **Nombre del campo** | `substance_identifier_field_key`, no `searchText`. |
| **Status 403 falso** | El POST de acción reporta 403 pero sirve el HTML completo. No fiarse del código de estado. |

---

## Campos del formulario (portlet `disslists_WAR_disslistsportlet`)

| Campo | Para qué |
|---|---|
| `_disslists_WAR_disslistsportlet_substance_identifier_field_key` | término de búsqueda (CAS, EC name, EC/Index number) |
| `_disslists_WAR_disslistsportlet_haz_detailed_concern` | motivo de inclusión (Art. 57a–f), vacío = todos |
| `_disslists_WAR_disslistsportlet_dte_inclusionFrom` / `_dte_inclusionTo` | rango de fecha de inclusión |
| `_disslists_WAR_disslistsportlet_formDate` | timestamp de sesión (dinámico) |
| `_disslists_WAR_disslistsportlet_deltaParamValue` | tamaño de página (default 50) |
| `doSearch` | `true` |
| `p_auth` (en la URL) | token CSRF de Liferay (dinámico) |

---

## Script verificado

```bash
#!/usr/bin/env bash
# uso: ./echa.sh "110-54-3"
set -e
CAS="${1:-110-54-3}"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"
P="_disslists_WAR_disslistsportlet"
BASE="https://www.echa.europa.eu/web/guest/candidate-list-table"
JAR=$(mktemp)

# 1) GET base -> cookies + token (sin WAF)
PAGE=$(curl -s -c "$JAR" -A "$UA" "$BASE")
PAUTH=$(grep -o 'p_auth=[A-Za-z0-9]*' <<<"$PAGE" | head -1 | cut -d= -f2)
FORMDATE=$(grep -o 'formDate[^0-9]*[0-9]\{10,\}' <<<"$PAGE" | grep -o '[0-9]\{10,\}' | head -1)

# 2) POST de busqueda (reusando cookies + p_auth). El 403 es falso: parsear body.
ACTION="$BASE?p_p_id=${P}&p_p_lifecycle=1&p_p_state=normal&p_p_mode=view&${P}_javax.portlet.action=searchDissLists&p_auth=${PAUTH}"
curl -s -b "$JAR" -A "$UA" -H "Referer: $BASE" \
  --data-urlencode "${P}_formDate=${FORMDATE}" \
  --data-urlencode "${P}_substance_identifier_field_key=${CAS}" \
  --data-urlencode "${P}_deltaParamValue=50" \
  --data-urlencode "doSearch=true" \
  "$ACTION" > result.html

# 3) extraer la(s) fila(s)
python3 - "$CAS" <<'PY'
import re,html,sys
cas=sys.argv[1]; t=open('result.html',encoding='utf-8',errors='ignore').read()
for m in re.finditer(r'<tr[^>]*>(.*?)</tr>', t, re.S):
    cells=[re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>','',c))).strip()
           for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', m.group(1), re.S)]
    cells=[c for c in cells if c]
    if any(cas in c for c in cells):
        print(' | '.join(cells))
PY
```

### Salida para `110-54-3`

```
n-hexane | 203-777-6 | 110-54-3 | 04-Feb-2026 | Specific target organ toxicity after repeated exposure (Article 57(f) - human health) | D(2025)7771-DC | View Details
```

Columnas: **nombre | EC number | CAS | fecha de inclusión | motivo (Art. 57) | nº decisión | detalle**.

---

## Cómo llegamos aquí (proceso paso a paso)

El proceso fue iterativo; cada paso descartó una hipótesis y reveló la siguiente pista.

### Paso 0 — Punto de partida equivocado
Arrancamos con la URL de `webtools.europa.eu/rest/requests/files?...`. Decodificamos el
`ref` en base64 → `https://www.echa.europa.eu`. Probamos con `curl`:
```
HTTP 403
```
**Conclusión:** no era la búsqueda, sino el servicio de cookies/analytics (EAMS). Descartado.

### Paso 1 — Buscar la API real
Búsqueda web + sondeo de endpoints de ECHA CHEM:
```bash
curl -s -o /dev/null -w "HTTP %{http_code}  type=%{content_type}\n" \
  "https://chem.echa.europa.eu/api-substance/v1/substance?searchText=110-54-3"
# -> HTTP 200  application/json
```
Devolvía JSON limpio con la identidad del n-hexano (CAS, EC, fórmula, SMILES, InChI).
**Pista:** existe una API sin WAF... pero ¿es la Candidate List? (spoiler: no).

### Paso 2 — La URL verdadera resultó ser un portlet Liferay
El usuario aportó la URL real: `candidate-list-table?...javax.portlet.action=searchDissLists`.
Probamos GET y POST en frío a esa URL de **acción**:
```
GET  -> HTTP 403
POST -> <title>Azure WAF</title>  (JS Challenge)
```
**Conclusión:** la URL de acción está tras **Azure WAF**. Un `curl` ciego no pasa.

### Paso 3 — El formulario reveló los nombres reales
Con el `<form>` completo descubrimos tres cosas críticas:
- El campo es `substance_identifier_field_key`, **no** `searchText` (por eso el POST del paso 2 no habría servido aunque pasara el WAF).
- Existe `p_auth=...` en el `action` → token CSRF de Liferay.
- Existe `formDate=...` → timestamp de sesión.

### Paso 4 — Verificar que el dato existe (sin pelear con el WAF)
Antes de seguir, confirmamos por búsqueda web que el n-hexano **sí** está en la lista
(añadido 04-Feb-2026, Art. 57(f)). Evita perseguir un resultado vacío legítimo.

### Paso 5 — La hipótesis ganadora: GET base → token → POST
Probamos la **página base** (sin params de acción) con cookie jar y UA de navegador:
```bash
curl -s -c echa_cookies.txt -A "$UA" \
  -w "HTTP %{http_code}  size=%{size_download}\n" \
  "https://www.echa.europa.eu/web/guest/candidate-list-table" -o echa_page.html
# -> HTTP 200  size=411857   (title real, 0 coincidencias WAF)
grep -o 'p_auth=[A-Za-z0-9]*' echa_page.html   # -> p_auth=POYF2dnl
```
**¡Hallazgo clave!** La página base **no dispara el WAF** y entrega `p_auth` + `formDate` + cookies.

### Paso 6 — POST reusando token + cookies
Primer intento dio `HTTP 502` (gateway transitorio). Reintento: `HTTP 200`.
Capturamos el cuerpo y parseamos la tabla → apareció la fila del n-hexano completa.

### Paso 7 — El status 403 "falso"
En corridas posteriores el POST reportaba `HTTP 403` con un cuerpo de ~415 KB.
Al inspeccionar el body: `<title>` real, **0 coincidencias WAF**, y la fila del n-hexano presente.
**Conclusión final:** no fiarse del status code; **parsear el cuerpo**. Y **no usar `-L`**,
porque el redirect final sí cae en un 403 real del WAF.

### Resumen de la cadena de pistas
```
webtools/EAMS (403, ruido)
   └─> api-substance (200 JSON, pero solo identidad, no la lista)
          └─> portlet de acción (403 / WAF en frío)
                 └─> form HTML (campo real + p_auth + formDate)
                        └─> página BASE (200, sin WAF, da token+cookies)
                               └─> POST acción con token+cookies -> body con resultados (ignorar 403)
```

---

## Notas de robustez

- `p_auth` y `formDate` **caducan**: hacer el GET justo antes del POST, no cachearlos.
- **No usar `-L`**: el redirect final cae en un 403 real del WAF. La respuesta directa del POST ya trae todo.
- Más de 50 resultados → subir `deltaParamValue` o paginar.
- "View Details" enlaza al dossier: `/candidate-list-table/-/dislist/details/<id>`.
- El portal viejo (`www.echa.europa.eu`) es **legado**: ECHA lo mantiene hasta **julio 2026**. La versión nueva es el SPA `https://chem.echa.europa.eu/obligation-lists/candidateList` (descubrir su XHR real interceptando el tráfico con un navegador headless si se quiere migrar).

---

## Dato confirmado (n-hexano)

- **CAS**: 110-54-3 · **EC**: 203-777-6 · **Fórmula**: C6H14
- **Añadido a la Candidate List**: 4 de febrero de 2026
- **Motivo**: Specific target organ toxicity after repeated exposure — Article 57(f), equivalent level of concern (human health)

Fuentes: chem.echa.europa.eu · echa.europa.eu/candidate-list-table
