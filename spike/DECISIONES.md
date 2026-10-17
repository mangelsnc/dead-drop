# DECISIONES.md — Spike técnico: QR animados + cifrado E2E

> **Estado:** validado por simulación. 12/12 tests en verde. Métricas en
> `spike/src/benchmark_results.json`.
>
> **Pregunta que responde este spike:** ¿puede un archivo cifrado cruzar de
> una pantalla a una cámara, sin red, a una velocidad usable por una persona
> no técnica? **Respuesta: sí — ~4 KB/s efectivos, 8 KB en ~2 segundos.**

---

## 1. Cifrado E2E: libsodium, X25519 efímero + XSalsa20-Poly1305 + Ed25519

**Decisión:** usar libsodium (PyNaCl en el spike, `sodium_libs` en Flutter)
con esta pila concreta:

| Pieza | Primitiva | Por qué |
|---|---|---|
| Intercambio de claves | **X25519** (`crypto_box`) | Clave efímera por transferencia → *forward secrecy* gratis. Nada que almacenar, nada que filtrar después. |
| Cifrado simétrico | **XSalsa20-Poly1305** (AEAD) | Cada chunk va autenticado: un frame dañado se **detecta y descarta**, nunca corrompe el archivo silenciosamente. Nonce de 192 bits → aleatorio sin riesgo de colisión. |
| Firma del manifiesto | **Ed25519** | El receptor sabe que el archivo viene de la persona que tiene delante (autenticidad de emisor), no solo que "alguien lo cifró". |
| Integridad final | **SHA-256** del plaintext, firmado | Verificación de extremo a extremo independiente del transporte. |

**Por qué libsodium y no otra cosa:**
- Es la referencia en cripto aplicada: API difícil de usar mal, sin
  algoritmos legacy peligrosos que elegir por error.
- Mismo backend en todos los targets de Flutter vía `sodium_libs`
  (iOS/Android/desktop) → el spike mide lo que el producto hará.
- Auditada, madura, y su filosofía "sin opciones" encaja con el requisito
  de app para público no técnico: nosotros elegimos, el usuario no.

**Alternativas descartadas:**
- *AES-GCM "a mano"*: nonce de 96 bits obliga a gestión de contador
  estricta; un fallo destruye la confidencialidad. XSalsa20 lo evita por
  diseño.
- *RSA/OAEP*: claves enormes (un QR de bootstrap de 400+ bytes vs 179),
  sin forward secrecy sin trucos, más lento.
- *age / PGP*: orientados a ficheros con formato propio; aquí necesitamos
  control total del wire format para meterlo en QRs.

---

## 2. Canal unidireccional: fountain code (LT) en lugar de repetición

**El problema:** la pantalla emite, la cámara recibe. **No hay canal de
retorno** — el receptor no puede pedir "repite el frame 42". Es un
broadcast con pérdidas.

**Opciones evaluadas:**

| Estrategia | Overhead para K chunks | Veredicto |
|---|---|---|
| Secuencia simple en bucle | ~K·ln(K) recepciones (coupon collector). K=100 → ~460 frames, **4.6× de desperdicio** | ❌ |
| Reed–Solomon systematic (K+ε fijos) | ~1.05× pero hay que acordar ε de antemano y re-hacer si no basta | ⚠️ rígido |
| **LT code (Luby Transform)** | **~1.1–1.3×, ilimitado, cualquier frame sirve** | ✅ |
| RaptorQ (RFC 6330) | ~1.02×, óptimo teórico | 🔜 producción (ver abajo) |

**Decisión: LT code con distribución robust-soliton**, implementado en
`fountain.py`:

- El emisor genera un stream **infinito** de frames; cada frame es el XOR
  de un subconjunto pseudo-aleatorio de los K chunks fuente.
- El receptor decodifica por *belief propagation* (peeling): cada frame de
  grado 1 revela un chunk, que a su vez simplifica los demás.
- El receptor necesita **cualquier** conjunto de ~K·(1+ε) frames — da igual
  cuáles se perdieron. Esto elimina el coupon-collector.

**Medido en el simulador (8 KB, 512 B/chunk, 10% pérdida):**
overhead **1.31×** — es decir, 21 frames entregados para 16 chunks.
A 50% de pérdida brutal el canal sigue completando (2.56× overhead).

**Por qué LT y no RaptorQ ya:** RaptorQ añade un *precode* (LDPC) que exige
resolver un sistema lineal — más código, más superficie de bug, y para un
spike la ganancia (1.31× → 1.05×) no justifica el riesgo. **El plan de
producto es migrar a RaptorQ** (hay crates y ports de referencia) una vez
validado el canal; la interfaz `LTEncoder`/`LTDecoder` ya está pensada
para intercambiar el codec sin tocar emisor ni receptor.

**Bug real encontrado en el spike:** la robust-soliton desbordaba para K
pequeño (pivot > K). Corregido con clamp — exactamente el tipo de cosa que
un spike existe para encontrar.

---

## 3. Formato de QR: binario, EC-M, ~512 B de payload por frame

**Decisión:** modo **byte (8-bit)**, corrección de errores **M (15%)**,
auto-fit de versión, payload objetivo **512 bytes/chunk**.

**Por qué:**
- *Modo byte*: el ciphertext es arbitrario; los modos numeric/alphanumeric
  no aplican y kanji no aporta nada portable.
- *EC-M*: punto dulce medido. EC-L da más capacidad pero falla más con
  brillo/ángulo; EC-H aguanta más pero el QR se vuelve denso y lento de
  escanear. En el benchmark, M equilibra throughput y robustez.
- *512 B/chunk*: un frame completo (header + nonce + tag + payload) son
  ~577 bytes → cabe holgado en un **QR v25-M (capacidad 1003 B)**, que una
  cámara de gama media escanea a 10–15 fps sin esfuerzo. Chunks de 1024 B
  dan más throughput bruto (5.8 KB/s en simulación) pero empeoran la
  eficiencia del fountain para ficheros pequeños (overhead 1.62×) y exigen
  QRs más densos. **512 B es el default del producto.**

**Frame binario (big-endian):**
```
MAGIC(2) "DD" | version(1) | file_id(8) | seq(4) | seed(4)
| degree(2) | chunk_ids(2×degree) | nonce(24) | ciphertext+tag(N)
```
El `file_id` permite al receptor ignorar frames de otra sesión cercana
(dos transferencias en la misma sala). El `seed` permite en producción
reconstruir los `chunk_ids` sin transmitirlos (ahorro de bytes) — en el
spike los llevamos explícitos por depurabilidad.

---

## 4. Bootstrap de sesión: un QR estático primero

Antes de la secuencia animada, el emisor muestra **un solo QR estático**
(179 bytes medidos) con: clave pública efímera, clave pública del receptor
(binding — solo ese receptor puede descifrar), metadatos del fichero y la
firma Ed25519 del manifiesto.

Esto resuelve el arranque en frío: el receptor apunta, lee un QR, y ya
tiene todo lo necesario para decodificar el stream animado que viene
detrás. La clave del receptor se comparte fuera de banda (la muestra en su
pantalla, o se intercambia al inicio del encuentro).

---

## 5. Resultados del benchmark (simulador, 12 fps)

| Fichero | Chunks | Tiempo | Throughput | Overhead fountain |
|---|---|---|---|---|
| 1 KB | 2 | 0.17 s | 6.1 KB/s | 1.00× |
| 8 KB | 16 | **2.1 s** | **3.9 KB/s** | 1.31× |
| 10 KB | 20 | 4.0 s | 2.6 KB/s | 2.05× |
| 25 KB | 50 | 5.9 s | 4.3 KB/s | 1.22× |
| 50 KB | 100 | 12.2 s | 4.2 KB/s | 1.25× |

**Lectura de producto:**
- **El caso de uso objetivo (documentos, claves, mensajes, fotos pequeñas
  < 25 KB) cruza en 2–6 segundos.** Es usable.
- El canal **tolera hasta 50% de pérdida de frames** y aun así completa.
- La corrupción de bits **nunca** produce un fichero corrupto silencioso:
  el AEAD lo descarta (verificado en `test_corruption_never_corrupts_file`).
- **Tamaño máximo práctico:** ~50–100 KB por transferencia con la UX
  actual (12–25 s sosteniendo el móvil). Ficheros mayores → troceado en
  varias sesiones o compresión previa (trabajo futuro).

---

## 6. Plan de port a Flutter (producción)

La lógica core del spike es **portable 1:1** — no depende de Python más
allá de la sintaxis:

| Spike (Python) | Producción (Flutter/Dart) |
|---|---|
| PyNaCl | `sodium_libs` (mismo libsodium) |
| `qrcode` (PIL) | `qr_flutter` (render) |
| simulador de canal | `mobile_scanner` / `camera` (captura real) |
| `fountain.py` LT | port directo a Dart (puro, sin deps) |
| CLI | UI Flutter: pantalla emisora animada + vista de cámara receptora |

**Lo que el spike NO cubre y queda para la fase 2:**
- Rendimiento real de escaneo en dispositivos físicos (fps sostenido,
  auto-enfoque, tolerancia a ángulo). El simulador asume 12 fps; hay que
  medirlo en hardware.
- Migración LT → RaptorQ si el overhead importa.
- Compresión previa (zlib/zstd) para ficheros de texto.
- Modo duress y autodestrucción (capa de producto, no de transporte).
