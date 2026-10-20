# DeadDrop — Registro de riesgos
**Mantenido por:** Sara Quintana (COO) · **Revisión:** semanal (miércoles) · Escala P/I: baja / media / alta

## R1 — Throughput de QR animados insuficiente ⚠️ (riesgo estrella)
- **Probabilidad: media · Impacto: alto**
- **Descripción:** la tasa real de transferencia cámara↔pantalla puede quedar muy por debajo de lo usable (p. ej. <1 KB/s efectivos), haciendo inviables archivos >100KB y dañando la propuesta de valor.
- **Señal temprana:** números del spike de Marco (S1–S2).
- **Mitigación:** (a) medir primero, diseñar después — la spec no cierra parámetros hasta tener datos; (b) fountain codes (RaptorQ/LT) para tolerar frames perdidos sin retransmisión; (c) modo bidireccional alternando roles emisor/receptor; (d) degradación elegante: si el throughput es bajo, posicionar DeadDrop para archivos pequeños críticos (claves, documentos, pruebas) y decirlo honestamente en la submission; (e) ajuste de densidad QR vs fiabilidad por calidad de cámara.

## R2 — Complejidad del modo coacción
- **Probabilidad: alta · Impacto: alto**
- **Descripción:** un entorno falso poco convincente es peor que no tenerlo (expone al usuario). Es la feature más delicada y la que más fácil se subestima.
- **Señal temprana:** diseño de Lía (S3) revela casos imposibles de resolver de forma creíble.
- **Mitigación:** (a) diseño detallado ANTES de implementar (tarea dedicada con modelo de amenaza); (b) alcance mínimo convincente: mejor pocos archivos señuelo coherentes que un universo falso a medias; (c) comportamiento indistinguible como requisito de aceptación (mismos tiempos, mismos errores); (d) si no alcanza el listón para el MVP, se documenta como 'trabajo futuro' en la submission en vez de entregarlo mal; (e) precedentes estudiados: VeraCrypt hidden volumes, Rubberhose.

## R3 — Builds reproducibles multiplataforma
- **Probabilidad: media · Impacto: medio-alto** (criterio explícito del jurado)
- **Descripción:** Flutter + dependencias nativas (libsodium) en Windows/macOS/Linux puede producir builds no deterministas o toolchain frágil; verificabilidad comprometida.
- **Señal temprana:** CI inicial (S3) produce hashes distintos entre runners o entre CI y local.
- **Mitigación:** (a) fijar versiones exactas de toolchain (Flutter SDK, compiladores) en CI; (b) publicar SHA-256 de artifacts y documentar verificación local; (c) contenedores/entornos herméticos de build donde sea posible; (d) empezar el CI en S3, no al final — el tiempo de debug de reproducibilidad es impredecible.

## R4 — Alcance multiplataforma sobredimensionado
- **Probabilidad: media · Impacto: medio**
- **Descripción:** Windows+macOS+Linux es requisito; Android/iOS puntúan extra pero pueden comer el calendario.
- **Mitigación:** desktop primero (requisito), móvil solo si sobra buffer. Decisión explícita en S6: si el prototipo desktop no es demo-able, móvil queda fuera del MVP y se menciona como roadmap.

## R5 — Usabilidad insuficiente para no técnicos
- **Probabilidad: media · Impacto: alto** (criterio explícito del jurado)
- **Descripción:** que la app requiera conceptos técnicos (claves, cifrado) mata el criterio de 'facilidad de uso'.
- **Señal temprana:** test de usabilidad S5 con 5 usuarios no técnicos.
- **Mitigación:** (a) test de usabilidad ANTES de enviar la idea, no después; (b) regla de diseño: cero terminología crypto visible; (c) iteración de mockups según hallazgos con una semana reservada (S6).

## R6 — Retraso en el camino crítico (spike → spec → prototipo)
- **Probabilidad: media · Impacto: alto**
- **Descripción:** Marco concentra el camino crítico; un atasco en el spike retrasa spec, prototipo y demo.
- **Mitigación:** (a) 2 semanas de buffer (S9–S10) + envío interno adelantado al 21-dic; (b) regla de desviación >3 días → replanificación inmediata; (c) Marco tiene 2 slots pero Sara vigila que no se solapen dos tareas críticas; (d) si el spike se atasca, Marco prototipa la lógica core en Dart/Python puro y documenta el plan de port (ya previsto en su briefing).

## R7 — Objeción legal/ética al modo coacción o al cifrado
- **Probabilidad: baja-media · Impacto: alto** (requisito '100% legal y ético')
- **Descripción:** el jurado podría cuestionar la negación plausible o el doble uso.
- **Mitigación:** (a) revisión legal y ética documentada (tarea de Vera, S3) con marco España/UE y precedentes; (b) declaración ética en la submission; (c) diseño que desincentiva uso indebido sin dañar a usuarios legítimos; (d) mapeo explícito a DUDH art. 12/19/20 que el propio reto cita.

## R8 — Dependencia de una sola persona (Miguel Ángel) para decisiones
- **Probabilidad: media · Impacto: medio**
- **Descripción:** cualquier decisión no resoluble internamente espera email a Miguel Ángel; si tarda, el trabajo se frena.
- **Mitigación:** (a) formato de escalado con opciones + recomendación + deadline de decisión (tarea de comunicación de Sara); (b) las decisiones escaladas nunca bloquean todo el tablero: Sara reasigna trabajo útil en <24h (regla de oro); (c) agrupar decisiones en un solo email semanal cuando sea posible.

## R9 — Submission débil por falta de evidencias
- **Probabilidad: baja-media · Impacto: alto**
- **Descripción:** una idea bien escrita pero sin prototipo, tests de usabilidad ni builds verificables puntúa peor en 'calidad técnica' y 'facilidad de uso'.
- **Mitigación:** (a) la submission es de las últimas tareas y depende explícitamente de propuesta, investigación y spec; (b) hito S6 'prototipo demo-able' y vídeo de 2 min como evidencia; (c) cifras del test de usabilidad citables ('Y% completó la transferencia sin ayuda').

## R10 — Agente sin trabajo / tablero muerto
- **Probabilidad: baja (con autoplay) · Impacto: medio**
- **Descripción:** alguien termina sus tareas y queda parado, perdiendo capacidad del equipo.
- **Mitigación:** (a) autoplay activo en los 4 agentes (2 slots cada uno) — verificado 17-oct; (b) revisión de tablero los lunes por Sara; (c) regla de oro: trabajo útil creado en <24h para quien se quede vacío; (d) cola de To Do con 12 tareas ya cargada el 17-oct.

---
**Resumen:** 10 riesgos, 3 de ellos (R1, R2, R3) son los señalados como críticos y tienen señal temprana en las próximas 3 semanas. Próxima revisión: miércoles 21-oct.
