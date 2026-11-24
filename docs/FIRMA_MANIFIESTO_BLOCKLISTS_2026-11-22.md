# Firma del manifiesto de blocklists

Fecha: 2026-11-22
Estado: **infraestructura implementada y probada; pendiente de configurar una
clave real y publicar el manifiesto firmado.**

## Por qué

El manifiesto actual se descarga por HTTPS y contiene un SHA-256 por feed. Eso
detecta corrupción y discrepancias entre manifiesto y feeds, pero no autentica
al editor: si el servidor o el DNS del host se comprometen, un atacante puede
servir un manifiesto y unos feeds coherentes entre sí y añadir dominios
maliciosos a la lista de bloqueo o quitar los legítimos.

La firma añade autenticidad: Aura solo acepta un manifiesto firmado por una
clave cuya parte pública viene compilada en la app.

## Formato

Archivo `<URL del manifiesto>.sig`, JSON compacto:

```json
{"algorithm":"RS256","key_id":"aura-2026-11","signature":"<base64>"}
```

- `RS256`: RSA PKCS#1 v1.5 con SHA-256 sobre los **bytes exactos** del
  manifiesto (el mismo archivo que se publica, sin reformatear).
- `key_id`: identificador de la clave, `[A-Za-z0-9._-]{1,64}`.
- `signature`: firma en base64.

La app compila una o varias claves públicas en
`AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS`, con formato:

```text
aura-2026-11:<base64 DER SubjectPublicKeyInfo>;aura-2027-03:<base64 DER ...>
```

Si la variable está vacía, el comportamiento anterior (solo SHA-256) se
mantiene y se registra una advertencia `The blocklist manifest is not signed`.
Si está configurada, la firma es **obligatoria**: un `.sig` ausente, con
`key_id` desconocido, algoritmo distinto o firma inválida aborta la
actualización y conserva la generación verificada anterior.

## Generar claves y firmar

```bash
# 1. Crear clave privada cifrada (0600) y pública. No se sobrescriben.
python3 tool/sign_blocklist_manifest.py generate \
  --private-key /ruta/segura/blocklist-private.pem \
  --public-key /ruta/segura/blocklist-public.pem

# 2. Firmar el manifiesto exacto que se va a publicar.
python3 tool/sign_blocklist_manifest.py sign \
  --manifest /ruta/manifest.json \
  --private-key /ruta/segura/blocklist-private.pem \
  --key-id aura-2026-11 \
  --output /ruta/manifest.json.sig

# 3. Verificar antes de subir.
python3 tool/sign_blocklist_manifest.py verify \
  --manifest /ruta/manifest.json \
  --signature /ruta/manifest.json.sig \
  --public-keys 'aura-2026-11:<base64>'
```

El comando `generate` imprime la cadena `keyId:base64` lista para pegar en
`AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS`. La contraseña se lee de
`AURA_SIGNING_PASSPHRASE` o se pide por terminal; nunca se pasa como argumento
para no dejarla en el historial del shell.

## Configurar la compilación

```bash
export AURA_BLOCKLIST_MANIFEST_URL="https://tu-host/aura/manifest.json"
export AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS="aura-2026-11:<base64>"
export PHISHTANK_APP_KEY="..."
flutter build apk --release
```

La URL de la firma se deriva insertando `.sig` antes de `?`/`#`; por ejemplo
`https://host/manifest.json?sig=1` usa `https://host/manifest.json.sig?sig=1`.
Debe servirse por HTTPS.

## Rotación

1. Generar un par nuevo con otro `key_id`.
2. Publicar `AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS` con **la clave vieja y la
   nueva** y lanzar una versión de la app.
3. Firmar los manifiestos nuevos con la clave nueva.
4. Esperar a que la adopción de la versión con ambas claves sea suficiente.
5. Retirar la clave vieja de la configuración y del archivo de firma.

Una firma con una clave retirada deja de aceptarse; el manifiesto anterior
sigue disponible como generación `previous`, pero no se usa para actualizar
hasta que llegue uno firmado con una clave vigente.

## Pruebas

- `tool/test_sign_blocklist_manifest.py`: firma/verificación, manifiesto
  alterado, `key_id` desconocido, rotación con dos claves y `key_id` duplicado.
- `Aura Android Debug Build` compila el servicio Kotlin y ejecuta sus pruebas
  unitarias/instrumentadas.
- No hay todavía una prueba de instrumentación que descargue un manifiesto real
  firmado; queda pendiente para la validación en el TECNO POVA 5.

## Límites honestos

- Mientras no se configure una clave y se publique `.sig`, la app sigue en modo
  heredado sin autenticidad de manifiesto. Es una decisión deliberada para no
  romper instalaciones existentes, no una protección activa.
- La seguridad de la clave privada es responsabilidad del operador. Debe vivir
  fuera del repositorio, con permisos restrictivos y respaldo cifrado.
- La firma no protege contra un atacante que controle la clave privada ni
  contra un `AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS` manipulado en una compilación
  no oficial. La app debe distribuirse firmada por el canal oficial.
