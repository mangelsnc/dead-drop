# DeadDrop

**Pasa archivos de un dispositivo a otro sin internet, sin cables, sin Bluetooth. Solo la pantalla y la cámara.**

Y si alguien te obliga a abrir la aplicación, un PIN señuelo muestra un contenido falso y convincente mientras tus archivos reales permanecen invisibles.

---

## ¿Por qué existe DeadDrop?

Imagina que tienes en tu portátil unos documentos que necesitas entregar **en mano** a otra persona que está a un metro de ti. Hoy tus opciones son malas:

- **Enviarlos por internet** (correo, WhatsApp, nube): aunque vayan cifrados, dejas un rastro permanente en servidores ajenos: quién envía, quién recibe, cuándo.
- **Bluetooth o AirDrop**: emiten señales detectables y quedan registrados en el sistema.
- **Un USB**: es lo primero que se incauta en un control, y un clásico para propagar virus.

DeadDrop resuelve esto: la pantalla de un dispositivo muestra códigos QR animados, la cámara del otro los lee, y el archivo pasa **protegido de extremo a extremo sin que un solo byte toque ninguna red**. Puedes activar el modo avión delante de cualquiera y la transferencia funciona igual.

**¿Para quién es?** Para la periodista que entrega una filtración a su redacción. Para el activista que pasa pruebas a un abogado. Para cualquier persona que quiere entregar sus documentos personales sin que pasen por servidores de terceros. La privacidad es un derecho (artículos 12, 19 y 20 de la Declaración Universal de Derechos Humanos), no un privilegio técnico.

---

## Cómo funciona en 30 segundos

```
  Dispositivo A (envía)                    Dispositivo B (recibe)
┌─────────────────────┐                  ┌─────────────────────┐
│                     │                  │                     │
│   ▓▓▓▓▓  ▓▓▓▓▓     │   solo luz,     │                     │
│   ▓ QR ▓→▓ QR ▓→   │ ═══════════════► │      📷 cámara      │
│   ▓▓▓▓▓  ▓▓▓▓▓     │   sin radio,     │                     │
│                     │   sin red        │                     │
└─────────────────────┘                  └─────────────────────┘
   Elige archivo → la pantalla              Apunta con la cámara
   muestra códigos animados                 → recibe el archivo
```

1. **Eliges el archivo** en el dispositivo que envía.
2. **Aparecen códigos QR animados** en su pantalla (el archivo viaja dentro de ellos, protegido para que solo el destinatario pueda abrirlo).
3. **El otro dispositivo apunta con su cámara** y recibe el archivo. Listo.

Sin cuentas, sin configuración, sin servidores, sin registros.

---

## Instalación

Descarga el instalador para tu sistema desde la página de [Releases](../../releases) (o compila desde el código fuente — ver [CONTRIBUTING.md](CONTRIBUTING.md)):

### Windows
1. Descarga `DeadDrop-x.y.z-windows.exe`.
2. Ejecútalo (si Windows SmartScreen avisa, pulsa "Más información" → "Ejecutar de todas formas").
3. Abre DeadDrop desde el menú Inicio.

### macOS
1. Descarga `DeadDrop-x.y.z-macos.dmg`.
2. Arrastra DeadDrop a la carpeta Aplicaciones.
3. La primera vez, ábrelo con clic derecho → "Abrir" (Gatekeeper lo exige en apps sin notarizar).

### Linux
1. Descarga `DeadDrop-x.y.z-linux.AppImage` (o `.deb`).
2. Dale permisos de ejecución: `chmod +x DeadDrop-*.AppImage`.
3. Ejecútalo con doble clic.

> **Verificación:** cada release publica los checksums SHA-256 de los binarios y las instrucciones para reproducir la compilación desde el código fuente. Ver [docs/security.md](docs/security.md).

---

## Primer uso en 2 minutos

1. **Abre DeadDrop en ambos dispositivos.** No necesitas crear ninguna cuenta.
2. En el dispositivo que **envía**: pulsa **"Enviar un archivo"** y elige el archivo.
3. En el dispositivo que **recibe**: pulsa **"Recibir un archivo"** y apunta con la cámara a la pantalla del otro.
4. Verás una barra de progreso en ambos. Al terminar, el receptor pulsa **"Guardar"** y elige dónde.

Eso es todo. La [guía de uso completa](docs/user-guide.md) explica cada paso con capturas de pantalla, qué hacer si la cámara no lee bien, y cómo configurar el PIN señuelo.

---

## Preguntas rápidas

**¿Necesito internet?** No. Nunca. Ni para instalar la app (si la copias por USB), ni para usarla, ni para activarla.

**¿Qué pasa si me obligan a desbloquearla?** Puedes configurar un **PIN señuelo**: si lo introduces, la app se abre con normalidad pero muestra un contenido falso y creíble que tú eliges de antemano. Tus archivos reales no aparecen por ninguna parte. Más detalles en el [FAQ](docs/faq.md).

**¿Es legal?** Sí. DeadDrop es software libre (licencia MIT), auditable por cualquiera, y no oculta su propia existencia. Protege el mismo derecho que protege el correo postal sellado: la privacidad de la correspondencia. Ver el análisis completo en el [FAQ](docs/faq.md#es-legal).

Más respuestas en [docs/faq.md](docs/faq.md).

---

## Estado del proyecto

DeadDrop está en desarrollo activo para el reto **#cryptograFREE** (RootedCON + Criptored). Este repositorio es público desde el primer día y lo seguirá siendo para siempre.

- ✅ Documentación y propuesta de valor
- 🚧 MVP en desarrollo (entrega: febrero 2027)
- 📋 Roadmap: apps móviles Android/iOS tras el MVP

## Documentación

| Documento | Para quién |
|---|---|
| [docs/user-guide.md](docs/user-guide.md) | Cualquier persona que quiera usar la app, paso a paso y con capturas |
| [docs/faq.md](docs/faq.md) | Respuestas a las preguntas que todo el mundo hace |
| [docs/security.md](docs/security.md) | Qué protege y qué no protege DeadDrop — en llano y en versión técnica |
| [docs/value-proposition.md](docs/value-proposition.md) | Por qué existe el proyecto y qué lo hace distinto |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Cómo colaborar (código, traducciones, documentación) |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Normas de convivencia de la comunidad |

## Licencia

[MIT](LICENSE) — software libre, para siempre.

---

*DeadDrop no te hace invisible. Te devuelve algo que nunca debiste perder: la posibilidad de entregar información en mano sin que medio mundo lo sepa.*
