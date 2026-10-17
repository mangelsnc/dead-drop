# Seguridad en DeadDrop

Este documento explica **qué protege DeadDrop, contra quién, y qué no protege**. Está en dos partes:

1. **En llano** — para cualquier persona que use la app y quiera entender qué puede esperar de ella.
2. **Versión técnica** — para auditores, investigadores de seguridad y el jurado del reto.

La honestidad sobre los límites es tan importante como las garantías. Una herramienta de privacidad que promete lo imposible es una herramienta peligrosa.

---

# Parte 1 — En llano

## Qué protege DeadDrop

### 1. El contenido de tus archivos durante la entrega

Cuando pasas un archivo con DeadDrop, el contenido viaja protegido de extremo a extremo: se cierra en el dispositivo que envía y solo se abre en el dispositivo que recibe. Nadie en medio —ni siquiera alguien que grabe la pantalla con otra cámara— puede leerlo.

### 2. La inexistencia de rastro en la red

DeadDrop no usa internet, ni WiFi, ni Bluetooth, ni cables. El archivo viaja por la luz: de la pantalla a la cámara. Eso significa que **no hay metadatos en ningún servidor**: ninguna empresa ni ningún observador de la red puede saber que la transferencia ocurrió, quién participó, ni cuándo. No es que el rastro esté escondido: es que no existe.

### 3. Tu dispositivo ante un registro forzado

Con el **PIN señuelo** configurado, si te obligan a abrir la app puedes mostrar un contenido falso y creíble mientras tus archivos reales permanecen invisibles. Y con la **autodestrucción** activada, varios intentos fallidos de PIN borran el contenido protegido de forma irreversible.

### 4. La integridad del archivo

DeadDrop comprueba que lo que llega es exactamente lo que salió. Si falta aunque sea un byte, la app te avisa en lugar de entregarte un archivo corrupto o manipulado.

## Qué NO protege DeadDrop

Esto es igual de importante. DeadDrop **no** te protege de:

- **Un dispositivo ya comprometido.** Si tu ordenador tiene un virus o malware instalado (un troyano, un registrador de teclas), ese malware puede leer tus archivos antes de que los envíes o después de que los recibas. DeadDrop protege el canal, no cura un dispositivo enfermo.
- **Cámaras en la habitación.** Si alguien graba físicamente la pantalla del emisor *y además* compromete el dispositivo receptor, podría combinar ambas cosas. Contra la vigilancia física del lugar, la defensa es elegir bien el lugar.
- **Que la otra persona revele el archivo.** Una vez recibido, el archivo está en manos del destinatario. DeadDrop no puede impedir que esa persona lo comparta, lo imprima o lo entregue. Confía en el destinatario como confiarías al entregarle un sobre en mano.
- **Tu comportamiento.** Si hablas de la transferencia por un teléfono intervenido, si quedas con el destinatario por canales vigilados, o si llevas el dispositivo a un control anunciado en tu propio correo, ninguna app puede ayudarte. La seguridad es una cadena: DeadDrop es el eslabón de la entrega, los demás eslabones son tuyos.
- **El análisis del dispositivo con tu PIN real.** Si te obligan a dar el PIN y das el real, el contenido real es visible. El PIN señuelo solo funciona si lo tienes configurado *antes* y si su contenido es creíble.

## Consejos de sentido común

- Configura el PIN señuelo **antes** de necesitarlo, no el día antes de un viaje.
- Mantén el contenido señuelo creíble y actualizado.
- Activa el modo avión en ambos dispositivos durante la transferencia si quieres una garantía visible y demostrable de que no hay red.
- Verifica las descargas con los checksums publicados (ver abajo).
- DeadDrop es una herramienta para la entrega en persona. Para comunicación a distancia, combínala con otras herramientas (Signal, Tor) que resuelven ese otro problema.

---

# Parte 2 — Versión técnica (para auditores)

> **Estado:** esta sección describe el diseño de seguridad del MVP. Los parámetros concretos se congelarán con la implementación y cualquier cambio se documentará aquí. El código es la referencia final; este documento es el mapa.

## Modelo de amenaza

DeadDrop está diseñado contra estos adversarios:

| Adversario | Capacidad asumida | Respuesta de DeadDrop |
|---|---|---|
| **Observador de red** (ISP, estado, empresa) | Ve y registra todo el tráfico de red de ambos dispositivos | No hay tráfico: el canal es óptico (pantalla → cámara). Ausencia de emisión verificable con analizador de espectro. |
| **Observador de proximidad RF** | Captura Bluetooth/WiFi/radio en la habitación | No hay radio en uso. |
| **Interceptador óptico** | Graba la pantalla emisora con una cámara durante toda la transferencia | El payload viaja cifrado E2E (ver abajo): la grabación solo produce ciphertext. |
| **Adversario con acceso físico al dispositivo** | Registra el dispositivo, instala la app, la inspecciona | Datos en reposo cifrados con clave derivada del PIN (Argon2id). PIN señuelo → negación plausible. Autodestrucción opcional tras N intentos. |
| **Adversario que coacciona al usuario** | Obliga a desbloquear la app | PIN señuelo abre un espacio señuelo indistinguible del real a nivel de comportamiento de la app. |

Fuera de alcance (declarado explícitamente):

- Dispositivo comprometido a nivel de SO/malware (rootkits, keyloggers, Pegasus). DeadDrop no puede proteger un host comprometido; reduce su exposición a red a cero durante la transferencia, que es lo que está en su mano.
- Adversario que combina grabación óptica completa **y** compromiso del dispositivo receptor **y** obtención de sus claves.
- Canal encubierto físico (análisis acústico/térmico/consumo eléctrico de la pantalla). Teórico, fuera del modelo para una herramienta de producto.

## Canal de datos

- **Dirección:** unidireccional emisor → receptor en el MVP (inversión de roles con un botón).
- **Medio:** códigos QR animados (variante de fountain/RaptorQ o Reed-Solomon sobre frames QR, con reanudación ante pérdida de frames — la decisión final de código de corrección se documentará con la implementación).
- **Handshake:** al inicio de la sesión, el receptor muestra un QR estático con su clave pública efímera; el emisor lo escanea. Ni siquiera las claves tocan una red.
- **Integridad de sesión:** el receptor confirma al final un hash del archivo recibido; el emisor lo muestra para comparación visual si se desea.

## Criptografía

Regla del proyecto: **libsodium con parámetros por defecto. Cero criptografía casera.**

| Uso | Primitiva (libsodium) |
|---|---|
| Acuerdo de clave de sesión | X25519 (`crypto_kx` / `crypto_box` según flujo final), claves efímeras por sesión → forward secrecy |
| Cifrado del payload | XSalsa20-Poly1305 (`crypto_secretstream` o `crypto_box`), AEAD con autenticación por chunk |
| Derivación de clave desde PIN (datos en reposo) | Argon2id (`crypto_pwhash`) con parámetros interactivos como mínimo |
| Datos en reposo | Base de datos cifrada con clave derivada del PIN; el espacio señuelo y el real usan claves derivadas de PIN distintos, sin artefacto que revele la existencia de dos espacios |
| Autodestrucción | Borrado de la clave envuelta + sobrescritura del almacén cifrado (secure erase a nivel de app; los límites del wear-leveling en flash se documentarán honestamente) |

## Negación plausible — propiedades

- Mismo binario, mismo flujo de desbloqueo para ambos PIN: ninguna diferencia de comportamiento, timing o interfaz delata qué PIN se introdujo.
- El espacio señuelo es un espacio real cifrado con su propia clave: no es un "modo oculto" detectable.
- La app no almacena ningún indicador de que existen dos espacios.

## Verificabilidad de builds

- **Builds reproducibles:** el binario publicado en Releases se puede regenerar desde el código fuente y el toolchain fijado (versiones pineadas), obteniendo un resultado idéntico byte a byte. Instrucciones en cada release.
- **Checksums SHA-256** publicados con cada binario, firmados con la clave del proyecto.
- **CI pública** en GitHub Actions: cualquiera puede inspeccionar cómo se construyó cada artefacto.
- **Licencia MIT**, repo público desde el primer commit del MVP: auditoría abierta permanente.

## Reporte de vulnerabilidades

Si encuentras un problema de seguridad, **no abras una issue pública**. Escríbenos a través del canal indicado en `SECURITY.md` (se publicará con el primer release) y seguiremos un proceso de divulgación coordinada.

---

*Última actualización: 2026-10-17. Este documento se versiona con el proyecto.*
