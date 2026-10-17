# DeadDrop — Propuesta de valor y narrativa

**Proyecto:** DeadDrop · Reto #cryptograFREE (RootedCON + Criptored)
**Versión:** 1.0 · **Fecha:** 2026-10-17
**Estado:** Documento rector para el envío de la idea (límite: 28-dic-2026) y guía de decisiones del proyecto.

---

## 1. Elevator pitch

> **DeadDrop es la primera app que permite pasar archivos cifrados de un dispositivo a otro sin tocar ninguna red, cable ni Bluetooth: solo la cámara y la pantalla.**
> **Y si te obligan a desbloquearla, un PIN señuelo abre un entorno falso convincente mientras tus datos reales permanecen invisibles.**

Dos frases. Dos promesas. La primera resuelve el problema técnico (transferencia verdaderamente air-gapped, usable por cualquiera). La segunda resuelve el problema humano (coacción física, el escenario que ninguna herramienta de cifrado convencional contempla).

---

## 2. El problema concreto que resolvemos

El cifrado moderno protege los datos **en tránsito por la red** y **en reposo en el disco**. Pero deja sin cubrir un momento crítico y cada vez más frecuente: **la entrega física de información sensible entre dos personas que no pueden permitirse dejar rastro en ninguna red**.

Hoy, si dos personas cara a cara quieren intercambiar un archivo sin exponerlo, sus opciones reales son malas:

- **Enviarlo por internet** (correo, mensajería, nube): deja metadatos en servidores de terceros, aunque el contenido vaya cifrado. Los metadatos delatan *quién habla con quién, cuándo y cuánto*.
- **Usar Bluetooth, AirDrop o red local**: emiten señales detectables, quedan registrados en logs del sistema y son interceptables en proximidad.
- **Usar un USB**: exige confianza en el hardware, es un vector clásico de malware (BadUSB, Stuxnet) y es la primera cosa que se incauta en un control.

### Escenario 1 — La periodista en zona hostil

María cubre corrupción en un país donde el registro de periodistas es rutina. Tiene en su portátil 4 GB de documentos filtrados que prueban el desvío de fondos públicos. Su fuente está en la misma ciudad y quiere una copia de respaldo antes de que María cruce la frontera. Enviarlos por internet —incluso por Signal o Tor— genera un patrón de tráfico detectable entre dos personas ya vigiladas. Un USB sería incautado en el primer control de carretera. Con DeadDrop, los dos portátiles se ponen frente a frente en una habitación, la pantalla de uno emite QR animados, la cámara del otro los lee, y los documentos pasan cifrados de extremo a extremo **sin que exista un solo byte en ninguna red**. Si María es detenida y forzada a desbloquear la app, introduce su PIN señuelo: se abre una carpeta con fotos de viaje y documentos anodinos. Los documentos reales no aparecen por ninguna parte.

### Escenario 2 — El activista bajo vigilancia

Karim organiza una red de apoyo a personas perseguidas. Su teléfono fue intervenido una vez; desde entonces asume que todo lo que transmite es leído. Necesita entregar a un abogado una lista de contactos y pruebas de detenciones arbitrarias. No puede usar internet, no puede usar Bluetooth (detectable en proximidad), no puede arriesgar un USB registrado. Con DeadDrop en dos móviles, la transferencia ocurre en silencio electromagnético: no hay emisión de radio, no hay log de conexión, no hay metadato. El modo coacción le da además una capa de negación plausible si el dispositivo es registrado en su presencia.

### Escenario 3 — El ciudadano común

Lucía acaba de firmar su divorcio y necesita entregar a su abogado documentos financieros personales. No es activista ni periodista: simplemente no quiere que sus nóminas y cuentas pasen por servidores de Google, Meta o Dropbox, ni que queden en el historial de "compartidos" de su móvil. DeadDrop le da la misma garantía que a María y a Karim, con una interfaz que no exige saber qué es una clave pública: abrir la app, elegir el archivo, acercar el otro dispositivo, listo.

**El patrón común:** las tres personas necesitan mover información sensible entre dos dispositivos físicamente próximos sin dejar rastro en ninguna infraestructura, y sin que la posesión de la app sea en sí misma una prueba incriminatoria. Hoy no existe ninguna herramienta de producto que resuelva esto.

---

## 3. Por qué ahora

El reto #cryptograFREE lo formula con precisión: la privacidad no es un lujo técnico, es un derecho fundamental en erosión acelerada.

- **Art. 12 de la DUDH:** *"Nadie será objeto de injerencias arbitrarias en su vida privada, su familia, su domicilio o su correspondencia."* La vigilancia masiva de metadatos convierte toda "correspondencia" digital en observable por diseño. DeadDrop restaura el art. 12 en el acto concreto de transferir un archivo: no hay correspondencia observable porque no hay canal.
- **Art. 19 de la DUDH:** *"Todo individuo tiene derecho a la libertad de opinión y de expresión; este derecho incluye el de no ser molestado a causa de sus opiniones, el de investigar y recibir informaciones y opiniones, y el de difundirlas, sin limitación de fronteras, por cualquier medio de expresión."* La frase "investigar y recibir informaciones" es exactamente lo que hace la periodista del escenario 1. La vigilancia de red convierte ese derecho en un riesgo físico. DeadDrop lo protege.
- **Art. 20 de la DUDH:** *"Toda persona tiene derecho a la libertad de reunión y de asociación pacíficas."* Los metadatos de red son el instrumento estándar para mapear redes de asociación. Una transferencia air-gapped no genera aristas en ningún grafo social observable.

El contexto que hace esto urgente:

- **Regulación de escaneo masivo en la UE** (el debate en torno a "Chat Control") normaliza la idea de que todo contenido digital debe ser inspeccionable. Aunque el cifrado de extremo a extremo sobreviva, la presión se desplaza a los metadatos y a los dispositivos.
- **El malware estatal comercial** (Pegasus y sucesores) ha demostrado que el dispositivo conectado es el eslabón débil. Reducir la superficie de exposición de red a cero durante la transferencia es una defensa estructural, no una configuración.
- **La coacción física es el vector olvidado.** El cifrado de disco se derrota con una orden judicial o una amenaza. La negación plausible bien implementada es la única respuesta técnica a ese vector, y hoy está reservada a expertos (VeraCrypt hidden volumes) con una UX hostil.

DeadDrop llega en el momento en que estas tres presiones convergen, y lo hace con una herramienta que una persona no técnica puede usar.

---

## 4. Diferenciación frente a lo que existe

### Estado del arte (resumen honesto)

| Herramienta | Qué hace | Por qué no resuelve el problema |
|---|---|---|
| **AirGap Vault/Wallet** | QR animados air-gapped | Solo para claves cripto y firmado de transacciones. No es una herramienta de transferencia de archivos general. |
| **libcimbar / txqr** | Transferencia unidireccional por códigos animados | Son librerías/prototipos de investigación, no producto. Sin cifrado E2E integrado, sin UX, sin multiplataforma empaquetada, sin modo coacción. |
| **magic-wormhole** | Transferencia P2P cifrada | Requiere internet y un servidor de rendezvous. Deja metadatos. |
| **OnionShare** | Compartir archivos vía Tor | Requiere red, Tor, y configuración que intimida a no técnicos. Deja patrones de tráfico. |
| **Snapdrop / LocalSend / AirDrop** | Transferencia en red local | No son air-gapped: emiten radio, quedan en logs, interceptables en proximidad. |
| **VeraCrypt (hidden volumes)** | Negación plausible en disco | No transfiere nada. UX extremadamente hostil. Solo escritorio. |
| **USB / tarjetas SD** | Transferencia física | Vector de malware, incautable, deja artefactos forenses en ambos sistemas. |

### La posición única de DeadDrop

DeadDrop es, a fecha de hoy, **la única herramienta que combina las cuatro propiedades siguientes en un solo producto open source y multiplataforma**:

1. **Air-gap real:** el canal de datos es óptico (pantalla → cámara). No hay radio, no hay cable, no hay red. La ausencia de emisión es verificable con un analizador de espectro.
2. **Cifrado de extremo a extremo** con libsodium (X25519 + XSalsa20-Poly1305), con intercambio de claves también óptico: ni siquiera las claves tocan una red.
3. **Negación plausible integrada:** PIN señuelo que abre un entorno señuelo creíble (no una carpeta vacía, que delataría el truco), con autodestrucción opcional tras N intentos fallidos.
4. **Diseñada para no técnicos:** flujo de tres pasos, sin configuración, sin conceptos criptográficos expuestos, documentación en lenguaje claro.

Las herramientas existentes resuelven **una** de estas cuatro. Ninguna resuelve las cuatro a la vez. Esa combinación es la contribución original de DeadDrop.

### Cobertura de categorías del reto

- **Anonymity:** no hay metadatos de red que anonimizar porque no hay red. Es anonimato estructural, no probabilístico.
- **Encryption:** E2E con libsodium, claves efímeras por sesión, forward secrecy.
- **Local machine:** todo ocurre en local; la app funciona 100% offline; negación plausible y autodestrucción protegen el dispositivo en sí.
- **Evasion:** evasión del canal de vigilancia por diseño (no hay canal), y evasión de la coacción física mediante el entorno señuelo.

Cuatro categorías con una sola solución end-to-end. Es exactamente el perfil que el reto premia.

---

## 5. Narrativa para el jurado

### La historia en tres actos

**Acto 1 — El momento incómodo (30 segundos).**
"Imagina que tienes en este portátil los documentos que prueban una corrupción. La persona que necesita una copia está a un metro de ti. Y aun así, en 2026, tu única opción segura es… mandarlos por internet, dejando un rastro permanente en servidores que no controlas. Eso es absurdo. DeadDrop lo arregla."

**Acto 2 — La demo en vivo (2 minutos).**
Dos dispositivos sobre la mesa del jurado. Modo avión activado en ambos, visible. Se elige un archivo, la pantalla empieza a emitir QR animados, el otro dispositivo lo recibe. Se abre el archivo. *Silencio electromagnético total, verificable.* Después, el golpe: "Ahora regístrame el móvil." Se introduce el PIN señuelo. Aparece un entorno falso convincente. "Los documentos reales no existen para ti."

**Acto 3 — El derecho (30 segundos).**
"Esto no es una herramienta para esconder crímenes. Es la herramienta que hace posible el artículo 19 de la Declaración Universal —investigar y recibir información sin ser molestado— en un mundo donde toda comunicación electrónica es observable por diseño. La periodista, el activista y la ciudadana común tienen el mismo derecho. DeadDrop se lo devuelve a los tres."

### Claves retóricas

- **Nunca decir "cifrado militar" ni "indescifrable".** Decir "cifrado de extremo a extremo con libsodium, la misma librería auditada que usan Signal y WireGuard". Credibilidad técnica sin marketing.
- **El air-gap se demuestra, no se afirma.** Modo avión visible + transferencia funcionando = prueba empírica ante el jurado.
- **El modo coacción es el diferenciador emocional.** El QR impresiona; el PIN señuelo es lo que se recuerda. Es la respuesta a "¿y si te obligan?".
- **Anticipar la objeción del "doble uso":** toda herramienta de privacidad (Tor, Signal, VeraCrypt) es de doble uso. El reto exige legalidad y ética: DeadDrop las cumple por diseño — es open source auditable, no exfiltra nada, no oculta su propia existencia, y su documentación enmarca el uso en derechos fundamentales. La respuesta a "¿y si la usa un delincuente?" es la misma que da la DUDH: el derecho a la privacidad no se condiciona a la inocencia previa.
- **Cuantificar la cobertura:** "4 de las 5 categorías del reto, con una sola solución end-to-end". Es la métrica que el jurado puntúa explícitamente.

### Tono

Sobrio, técnico pero traducido, con un anclaje emocional concreto (la periodista, no "los usuarios"). Cero jerga innecesaria; cuando un término técnico es inevitable (air-gap, negación plausible), se define en una frase la primera vez.

---

## 6. Alcance del MVP (entrega: 10-feb-2027)

### ✅ Entra en el MVP

| Funcionalidad | Justificación |
|---|---|
| **Transferencia unidireccional por QR animados** (emisor → receptor) | El núcleo. Protocolo con corrección de errores (Reed-Solomon o fountain codes), reanudación ante pérdida de frames, indicador de progreso. |
| **Cifrado E2E con libsodium** | X25519 para intercambio de claves (la clave pública del receptor se muestra como QR estático al inicio), XSalsa20-Poly1305 para el payload. Claves efímeras por sesión. |
| **Desktop: Windows, macOS, Linux** | Requisito no negociable del reto. Flutter lo cubre con una sola base de código. |
| **Modo coacción (PIN señuelo)** | Diferenciador clave. Un PIN real y un PIN señuelo; el señuelo abre un entorno con archivos señuelo configurables por el usuario. |
| **Autodestrucción opcional** | Tras N intentos de PIN incorrectos (configurable, desactivado por defecto). Borrado seguro de la base de datos cifrada. |
| **UX de 3 pasos** | Elegir archivo → mostrar QR → confirmar recepción. Sin configuración, sin cuentas, sin conceptos criptográficos visibles. |
| **Documentación para no técnicos** | Guía de instalación y uso con capturas, FAQ, y "guía de la periodista" (caso de uso narrado paso a paso). En español e inglés. |
| **Builds reproducibles + CI en GitHub Actions** | Criterio explícito del jurado ("verificabilidad de builds"). Binarios firmados con checksums publicados. |
| **Open source (MIT o Apache 2.0) desde el día 1** | Requisito no negociable del reto. Repo público desde el primer commit del MVP. |

### ❌ NO entra en el MVP (y por qué)

| Funcionalidad | Razón de exclusión |
|---|---|
| **Apps móviles Android/iOS** | El reto las puntúa como *extra*, no como requisito. Flutter facilita el port, pero certificar cámara + rendimiento en móviles duplica el esfuerzo de QA. Se anuncia como roadmap post-MVP para sumar puntos de visión sin arriesgar la fecha. |
| **Transferencia bidireccional simultánea** | Complejidad de protocolo (dos canales ópticos full-duplex) sin valor demostrativo proporcional. El MVP permite invertir roles con un botón. |
| **Steganografía (ocultar los QR en imágenes/vídeo)** | Categoría "stego" del reto. Tentador, pero es una segunda tesis entera. Se documenta como trabajo futuro para mostrar ambición sin comprometer el núcleo. |
| **Transferencia de carpetas / múltiples archivos** | El MVP soporta un archivo o un `.zip` creado por la propia app. La gestión nativa de árboles de directorios es post-MVP. |
| **Integración con gestores de contraseñas / hardware keys** | Fuera de alcance. El MVP usa PIN + cifrado local con clave derivada (Argon2). |
| **Modo "sala" (más de 2 dispositivos)** | Complejidad de protocolo y UX. Post-MVP. |
| **Traducciones más allá de ES/EN** | Post-MVP, vía comunidad. |

### Criterio de corte

Todo lo que no esté en la columna "Entra" y no sea imprescindible para que la demo del Acto 2 funcione delante del jurado, **no se construye antes del 10-feb-2027**. La prioridad absoluta es un núcleo pequeño, sólido, auditable y demostrable en vivo.

---

## Anexo — Decisiones que este documento gobierna

1. Cualquier propuesta de funcionalidad nueva se evalúa contra la sección 6: ¿está en "Entra"? Si no, ¿es imprescindible para la demo? Si la respuesta es no dos veces, se aparca.
2. Toda decisión técnica de cifrado se resuelve a favor de **libsodium con parámetros por defecto**. Cero criptografía casera.
3. Toda decisión de UX se resuelve a favor de **la persona no técnica del escenario 3**. Si Lucía no lo entiende, se rediseña.
4. Toda comunicación pública del proyecto usa la narrativa de la sección 5: derechos fundamentales primero, tecnología después.

---

*Documento vivo. Cambios relevantes se registran como nuevas versiones en este mismo archivo.*
