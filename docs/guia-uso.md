# Guía de uso de DeadDrop

Esta guía te lleva de la mano desde que abres la app por primera vez hasta que completas tu primera transferencia. **No necesitas saber nada de tecnología.** Si sabes hacer una foto con tu móvil o copiar un archivo en tu ordenador, sabes usar DeadDrop.

> **Nota:** las capturas de pantalla se añadirán cuando la app esté disponible. Cada paso describe exactamente lo que verás.

---

## Antes de empezar: qué necesitas

- **Dos dispositivos** con DeadDrop instalado (dos ordenadores, o un ordenador y un móvil cuando estén las apps móviles).
- Que el dispositivo que **recibe** tenga una **cámara** (la webcam del portátil vale).
- Los dos dispositivos en la **misma habitación**, uno frente al otro.

No necesitas internet. No necesitas WiFi. No necesitas Bluetooth. No necesitas crear ninguna cuenta. De hecho, si quieres comprobarlo, activa el modo avión en ambos dispositivos: DeadDrop funciona igual.

---

## Tu primera transferencia, paso a paso

### Paso 1 — Abre DeadDrop en los dos dispositivos

Al abrir la app verás una pantalla con dos botones grandes:

- **"Enviar un archivo"**
- **"Recibir un archivo"**

La primera vez, la app te pedirá que crees un **PIN de acceso**. Es el código que protege tus archivos guardados dentro de la app. Elige algo que recuerdes y que no sea tu fecha de cumpleaños. Más adelante podrás configurar también un **PIN señuelo** (lo explicamos en la sección "El PIN señuelo" más abajo).

### Paso 2 — En el dispositivo que ENVÍA

1. Pulsa **"Enviar un archivo"**.
2. Se abre el selector de archivos de tu sistema. Elige el archivo que quieres pasar.
3. La app te muestra una pantalla con el nombre del archivo y su tamaño. Pulsa **"Empezar envío"**.
4. La pantalla empieza a mostrar **códigos que cambian varias veces por segundo**, parecidos a códigos QR. Tu archivo está viajando dentro de esos códigos, protegido para que **solo el dispositivo que está enfrente pueda abrirlo** — aunque alguien grabara la pantalla con otra cámara, no podría leer el contenido.

### Paso 3 — En el dispositivo que RECIBE

1. Pulsa **"Recibir un archivo"**.
2. La app abre la cámara. **Apunta a la pantalla del otro dispositivo**, como si fueras a hacerle una foto al código.
3. En cuanto la cámara empiece a leer los códigos, verás una **barra de progreso** que avanza. Mantén el dispositivo quieto y enfocando.
4. Cuando la barra llega al 100%, la app comprueba que el archivo ha llegado completo e intacto, y te muestra su nombre y tamaño.
5. Pulsa **"Guardar"** y elige la carpeta donde quieres guardarlo. Listo.

### Paso 4 — Comprueba el archivo

Abre el archivo en el dispositivo receptor y comprueba que se ve correctamente. DeadDrop garantiza que el archivo llega idéntico al original: si falta aunque sea un solo byte, la app te avisa en lugar de entregarte un archivo corrupto.

---

## Consejos para que la lectura sea rápida

Los códigos de la pantalla viajan a través de la cámara, así que la calidad de la lectura depende de cosas muy físicas:

- **Distancia:** entre 15 y 30 centímetros entre pantalla y cámara suele ser lo ideal. Ni pegado ni lejos.
- **Luz:** evita reflejos en la pantalla del emisor. Si hay un foco de luz justo detrás del receptor, la cámara puede tener problemas. Cambia un poco el ángulo.
- **Brillo de pantalla:** súbelo al máximo en el dispositivo que envía. La app lo sube automáticamente durante el envío.
- **Quieto:** ambos dispositivos deben estar lo más quietos posible. Apoyarlos en una mesa ayuda mucho.
- **Velocidad:** si la cámara de tu dispositivo es antigua, la app reduce automáticamente la velocidad de los códigos para que dé tiempo a leerlos. También puedes ajustarla a mano en el emisor con el control "Velocidad de envío".

Si la transferencia se atasca en un porcentaje, no pasa nada: los códigos se repiten en bucle, así que en cuanto la cámara vuelva a leer bien, la barra seguirá avanzando desde donde estaba. **No necesitas empezar de cero.**

---

## El PIN señuelo: qué es y cómo se configura

DeadDrop te permite tener **dos PIN**:

- Tu **PIN real**: abre la app con tus archivos de verdad.
- Tu **PIN señuelo**: abre la app con un contenido falso que tú has preparado antes.

¿Para qué sirve? Para la situación en la que alguien te **obligue** a desbloquear la app: un control, un registro, una amenaza. Introduces el PIN señuelo y la app se abre con total normalidad, mostrando los archivos que tú dejaste ahí para ese caso. No hay ninguna pantalla de "modo oculto", ningún mensaje sospechoso, nada que delate que existe otro contenido. La app se comporta exactamente igual que con el PIN real.

### Cómo configurarlo

1. Abre DeadDrop con tu PIN real.
2. Ve a **Ajustes → PIN señuelo**.
3. Elige un PIN distinto del real (que no sea obvio ni parecido).
4. **Prepara el contenido señuelo:** la app te permite añadir archivos al espacio señuelo. Elige archivos creíbles y anodinos: fotos de vacaciones, documentos sin importancia, apuntes. Un espacio completamente vacío levantaría sospechas, así que dedica cinco minutos a esto.
5. A partir de ese momento, cada PIN abre su propio espacio. Nadie que no sepa los dos PIN puede saber que existen dos.

### Reglas de oro del PIN señuelo

- **Nunca lo escribas** junto al PIN real ni en el mismo sitio.
- **Mantén el contenido señuelo vivo:** si tus "fotos de vacaciones" son de hace tres años y no hay nada reciente, resulta extraño. Añade algún archivo de vez en cuando.
- **Ensaya:** introduce el PIN señuelo alguna vez para ver exactamente lo que vería otra persona. Debe parecer tu app de verdad.

---

## Autodestrucción (opcional, para situaciones de alto riesgo)

DeadDrop puede borrar de forma segura todo el contenido protegido si alguien introduce el PIN incorrecto demasiadas veces seguidas.

1. Ve a **Ajustes → Autodestrucción**.
2. Actívala y elige el número de intentos fallidos (por ejemplo, 5).
3. A partir de ahí, si alguien supera ese número de intentos, el contenido protegido se borra de forma irreversible.

**Aviso importante:** esta función es irreversible. Si la activas y olvidas tu PIN, perderás tus archivos para siempre. Está desactivada por defecto y solo recomendamos activarla si tu situación lo justifica.

---

## Preguntas habituales

¿Tengo dudas sobre si necesito internet, si es legal, qué pasa si me roban el dispositivo…? Todo eso está respondido en el [FAQ](faq.md).

¿Quieres entender qué protege exactamente DeadDrop y qué no? Lee [seguridad.md](seguridad.md), que lo explica primero en llano y luego en versión técnica.
