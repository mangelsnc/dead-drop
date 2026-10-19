# Preguntas frecuentes (FAQ)

Las preguntas que haría cualquier persona antes de usar DeadDrop, respondidas sin tecnicismos.

---

## Lo básico

### ¿Necesito internet para usar DeadDrop?

**No.** Ni para enviar, ni para recibir, ni para activar la app, ni para crear tu PIN. DeadDrop no se conecta a internet nunca: no tiene servidores, no tiene cuentas, no envía estadísticas. Puedes activar el modo avión y comprobar que funciona exactamente igual.

### ¿Cómo puede pasar un archivo sin internet ni Bluetooth ni cables?

Por la vista, literalmente. La pantalla del dispositivo que envía muestra códigos (parecidos a los QR de los restaurantes) que cambian varias veces por segundo. La cámara del dispositivo que recibe los va leyendo hasta reconstruir el archivo completo. Es como pasar una nota enseñándola a alguien que la copia, pero a velocidad de máquina.

### ¿Qué necesito para usarlo?

Dos dispositivos con DeadDrop instalado, y que el que recibe tenga cámara. Nada más: ni cuentas, ni contraseñas de servicios externos, ni configuración.

### ¿Es gratis?

Sí, y lo será siempre. DeadDrop es software libre con licencia MIT: cualquiera puede usarlo, copiarlo, estudiarlo y mejorarlo, gratis, para siempre.

### ¿Qué sistemas soporta?

Windows, macOS y Linux. Las versiones para Android y iOS están en el roadmap después del lanzamiento inicial.

### ¿Puedo enviar cualquier tipo de archivo?

Sí: documentos, fotos, vídeos, comprimidos… lo que sea. En la versión inicial se envía un archivo cada vez (si quieres enviar varios, la propia app puede empaquetarlos en un único `.zip`).

### ¿Hay límite de tamaño?

No hay un límite fijo, pero ten en cuenta que el archivo viaja por la cámara: un documento de unos pocos MB se transfiere en segundos o pocos minutos; un vídeo de varios GB tardaría mucho. DeadDrop está pensado para documentos e información sensible de tamaño razonable, no para pasarte la colección de películas.

---

## Privacidad y seguridad

### ¿Alguien puede interceptar mi archivo mientras lo envío?

Para leer los códigos, alguien tendría que **ver físicamente la pantalla** durante toda la transferencia (una cámara oculta en la habitación, por ejemplo). Pero aunque lo consiguiera, el contenido viaja protegido de extremo a extremo: **solo el dispositivo receptor que participó en esa transferencia puede abrirlo**. Una grabación de la pantalla sería un montón de códigos inútiles.

### ¿Queda algún rastro de la transferencia?

En internet: nada, porque no hay internet. En los dispositivos: la app no guarda un historial de lo que enviaste ni a quién. El archivo recibido queda donde tú decidas guardarlo, como cualquier archivo.

### ¿Qué pasa si me obligan a desbloquear la app?

Para eso existe el **PIN señuelo**. Puedes configurar un segundo PIN que abre la app mostrando un contenido falso y creíble que tú preparas de antemano (fotos anodinas, documentos sin importancia). Quien te obligue ve una app normal con contenido normal. Tus archivos reales no aparecen por ninguna parte y no hay forma de saber que existe otro espacio. Lee la [guía de uso](user-guide.md#the-decoy-pin-what-it-is-and-how-to-set-it-up) para configurarlo bien.

### ¿Qué pasa si pierdo o me roban el dispositivo?

Tus archivos guardados dentro de DeadDrop están protegidos por tu PIN. Sin él, no se pueden leer. Y si activas la **autodestrucción**, tras varios intentos fallidos de PIN el contenido protegido se borra de forma irreversible.

### ¿Y si olvido mi PIN?

No hay forma de recuperarlo. No existe una "pregunta de seguridad" ni un correo de recuperación, porque eso requeriría servidores y cuentas, es decir, exactamente lo que DeadDrop evita. **Anota tu PIN y guárdalo en un sitio seguro** (o usa un gestor de contraseñas). Si activaste la autodestrucción y fallas demasiadas veces, perderás el contenido.

### ¿Puedo fiarme del cifrado? ¿Quién lo ha revisado?

DeadDrop no inventa su propio cifrado: usa **libsodium**, una librería de criptografía auditada y usada por herramientas tan contrastadas como Signal y WireGuard. Además, todo el código de DeadDrop es público: cualquier experto del mundo puede revisarlo y auditarlo, y los binarios que descargas se pueden regenerar desde el código fuente para comprobar que son exactamente lo que dicen ser. Los detalles técnicos están en [security.md](security.md).

### ¿DeadDrop me hace anónimo en internet?

No, y es importante entenderlo: DeadDrop **no es una herramienta de internet**. No navega, no envía correos, no oculta tu IP. Hace una sola cosa y la hace bien: mover archivos entre dos dispositivos que están físicamente juntos sin tocar ninguna red. Para anonimato en internet existen otras herramientas (como Tor) que resuelven un problema distinto.

---

## Legalidad y ética

### ¿Es legal usar DeadDrop?

**Sí.** DeadDrop es software libre y público. No oculta su propia existencia, no explota ninguna vulnerabilidad, no accede a sistemas ajenos. Protege el mismo derecho que protege una carta sellada o una conversación en privado: el artículo 12 de la Declaración Universal de Derechos Humanos ("nadie será objeto de injerencias arbitrarias en su vida privada… ni en su correspondencia"). Usar cifrado es legal en la inmensa mayoría de los países, igual que lo es cerrar con llave tu propio diario.

### ¿Y si la usa alguien para algo ilegal?

Toda herramienta de privacidad es de "doble uso": el mismo cifrado que protege a una periodista protege a un delincuente, igual que un cuchillo de cocina sirve para cenar y para otras cosas. La respuesta de las sociedades democráticas siempre ha sido la misma: el derecho a la privacidad no se condiciona a demostrar antes que eres inocente. DeadDrop se enmarca explícitamente en los derechos fundamentales (artículos 12, 19 y 20 de la DUDH) y su desarrollo es abierto y auditable precisamente para eso.

### ¿Puedo usarlo en el trabajo / en mi país?

DeadDrop no hace nada que no puedas hacer ya con papel y una conversación cara a cara. Dicho esto: algunos países restringen el uso de cifrado, y algunas empresas tienen políticas sobre qué software se puede instalar. Infórmate de la normativa que te aplica. DeadDrop te da la herramienta; la responsabilidad de usarla conforme a tu ley es tuya.

---

## Problemas y casos prácticos

### La cámara no lee los códigos, ¿qué hago?

Lo más habitual, en orden:

1. **Sube el brillo** de la pantalla que envía (la app lo hace automáticamente).
2. **Separa un poco los dispositivos**: entre 15 y 30 cm suele ser lo ideal.
3. **Evita reflejos**: si una luz fuerte se refleja en la pantalla, cambia el ángulo.
4. **Baja la velocidad de envío** con el control "Velocidad" del emisor: las cámaras antiguas necesitan más tiempo por código.
5. Mantén ambos dispositivos **quietos**, apoyados si puedes.

La transferencia no se pierde: los códigos se repiten en bucle y la app retoma desde donde estaba.

### ¿Puedo pausar una transferencia y seguir después?

Sí. Si la transferencia se interrumpe (te mueves, se bloquea la cámara, contestas una llamada), al reanudarla el receptor sigue desde el punto donde se quedó. No empiezas de cero.

### ¿Puedo enviar a más de un dispositivo a la vez?

En la versión inicial, no: la transferencia es entre dos dispositivos. Si necesitas entregar el mismo archivo a tres personas, haces tres envíos (cada uno protegido de forma independiente para ese destinatario).

### ¿Por qué no tiene versión web?

Porque una web necesita internet, y DeadDrop existe precisamente para no tocar internet. Es una app que instalas y que funciona completamente en local.

### ¿Cómo sé que la app que descargué es la buena y no una copia modificada?

Cada versión publica sus **checksums** (una huella digital del archivo) y las instrucciones para verificarla. Además, las compilaciones son **reproducibles**: cualquiera puede generar el binario desde el código fuente público y comprobar que coincide byte a byte con el publicado. Los pasos concretos están en [security.md](security.md).

### ¿Quién está detrás del proyecto?

Un equipo que participa en el reto **#cryptograFREE** (RootedCON + Criptored), un concurso de herramientas de privacidad y cifrado libres. El código, las decisiones y la documentación son públicos desde el primer día en [github.com/mangelsnc/dead-drop](https://github.com/mangelsnc/dead-drop).

### ¿Cómo puedo ayudar?

Usándolo, contándolo, traduciendo, reportando errores o contribuyendo código. Todo está explicado en [CONTRIBUTING.md](../CONTRIBUTING.md).

---

¿Tu pregunta no está aquí? Abre una [issue en GitHub](https://github.com/mangelsnc/dead-drop/issues) y la respondemos.
