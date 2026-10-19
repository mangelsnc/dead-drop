# Cómo contribuir a DeadDrop

Gracias por querer ayudar. DeadDrop es un proyecto de software libre (MIT) construido para el reto **#cryptograFREE** (RootedCON + Criptored), y toda contribución es bienvenida: código, documentación, traducción, diseño, pruebas o difusión.

---

## Formas de contribuir (no todo es programar)

- **Reportar errores o proponer mejoras:** abre una [issue](https://github.com/mangelsnc/dead-drop/issues) describiendo qué pasaba, qué esperabas y en qué sistema.
- **Documentación:** si algo de la [guía de uso](docs/user-guide.md) o el [FAQ](docs/faq.md) te ha resultado confuso, mejorarlo es una contribución de primera clase. Este proyecto se evalúa precisamente por ser usable por gente no técnica.
- **Traducción:** la documentación base está en español e inglés. Más idiomas son bienvenidos.
- **Diseño y UX:** mockups, iconos, flujos más claros.
- **Código:** Dart/Flutter en la app, GitHub Actions en la CI.
- **Revisión de seguridad:** auditar el código es una de las mejores formas de ayudar. Para vulnerabilidades, **no uses issues públicas** — ver `SECURITY.md` cuando esté disponible.

## Principios del proyecto (léelos antes de proponer)

1. **La persona no técnica manda en la UX.** Si una funcionalidad no se puede explicar sin jerga criptográfica, no está lista. La pregunta de control es: "¿lo entendería alguien que no sabe qué es una clave pública?"
2. **Cero criptografía casera.** Todo lo criptográfico se resuelve con libsodium y sus parámetros por defecto.
3. **Cero red.** Ninguna funcionalidad puede requerir conectividad. Ninguna telemetría, ninguna cuenta, ningún servidor.
4. **Todo en público.** Decisiones, código y documentación viven en este repo desde el primer día.

## Flujo de trabajo

1. **Abre o comenta una issue** antes de ponerte a trabajar, para no duplicar esfuerzo.
2. **Haz fork y crea una rama** descriptiva: `fix/lectura-qr-baja-luz`, `docs/faq-legalidad`, etc.
3. **Commits claros:** formato `tipo: descripción breve` (ej. `feat: reanudar transferencia tras pausa`, `docs: capturas de la guía de uso`). Tipos: `feat`, `fix`, `docs`, `test`, `refactor`, `ci`.
4. **Abre un Pull Request** contra `main` describiendo qué cambia y por qué. Si toca UX, incluye capturas. Si toca criptografía, espera una revisión extra rigurosa — y prepárate para justificar por qué no basta con libsodium por defecto (pista: casi siempre basta).
5. La CI debe pasar (tests + build en Windows, macOS y Linux).

## Entorno de desarrollo

El stack es **Flutter** (Dart) + **libsodium**.

**Opción A — Docker (recomendada, sin instalar Flutter en tu máquina):**

```bash
# Requisito: solo Docker
git clone https://github.com/mangelsnc/dead-drop.git
cd dead-drop
make build-linux   # compila la app de escritorio Linux
make test          # tests
make analyze       # análisis estático
make shell         # shell interactivo dentro del contenedor
```

Guía completa en [docs/development.md](docs/development.md).

**Opción B — Flutter nativo:**

```bash
# Requisitos: Flutter SDK estable (ver versión fijada en el repo)
git clone https://github.com/mangelsnc/dead-drop.git
cd dead-drop/app
flutter pub get
flutter run            # ejecuta en tu plataforma
flutter test           # tests
```

Las builds reproducibles y la firma de binarios están documentadas en cada release y en [docs/security.md](docs/security.md).

## Estilo de código

- Dart: `flutter analyze` sin warnings, formateo con `dart format`.
- Comenta el *por qué*, no el *qué*.
- Sin dependencias nuevas sin discusión previa en issue: cada dependencia es superficie de auditoría.

## Código de conducta

Todo el que participa en DeadDrop acepta el [Código de Conducta](CODE_OF_CONDUCT.md). Resumen: respeto, sin excepciones.

## Licencia

Al contribuir aceptas que tu contribución se distribuya bajo la licencia [MIT](LICENSE) del proyecto, para siempre.
