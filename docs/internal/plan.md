# DeadDrop — Plan de proyecto
**Origen:** 17-oct-2026 · **Envío de idea:** 28-dic-2026 23:59 (peninsular) · **MVP:** 10-feb-2027 · **Fallo jurado:** 28-feb-2027 · **Entrega RootedCON:** 6-mar-2027

## Fases
- **Fase 1 — Idea y fundamentos** (17-oct → 28-dic-2026, 10 semanas + buffer): propuesta de valor, investigación, diseño completo, spike técnico, prototipo funcional, documentación pública, repo con CI, submission enviada.
- **Fase 2 — MVP** (29-dic-2026 → 10-feb-2027, 6 semanas, condicionada a selección): endurecimiento, modo coacción implementado, multiplataforma pulida, tests, builds reproducibles verificados.
- **Fase 3 — Presentación** (11-feb → 6-mar-2027): demo en vivo, materiales de charla ANON track.

## Hitos semanales — Fase 1
- **S1 (17–23 oct):** Spike técnico en marcha (Marco); propuesta de valor + investigación de usuarios (Vera); design system + flujos core (Lía); plan + riesgos + tablero vivo (Sara). ✔ arrancado
- **S2 (26 oct–1 nov):** Spike completado con números de throughput reales. Inicio spec técnica (Marco, dep: spike). Análisis competitivo (Vera). Mockups alta fidelidad (Lía, dep: design system). Plan categorías extra stego/evasion (Marco).
- **S3 (2–8 nov):** Spec técnica v1 cerrada. Mockups completos. Diseño del entorno falso de coacción (Lía, dep: investigación). Revisión legal y ética (Vera). Repo público + CI builds reproducibles (Marco, dep: spike).
- **S4 (9–15 nov):** Prototipo funcional end-to-end v0.1 (Marco, dep: spike + spec). Documentación pública v1: README/FAQ/guía (Vera). Infraestructura de comunicación (Sara).
- **S5 (16–22 nov):** Prototipo v0.2 con parámetros ajustados según spec. Test de usabilidad con 5 no-técnicos (Lía, dep: mockups). Primer borrador de submission (Vera).
- **S6 (23–29 nov):** **HITO: prototipo demo-able.** Vídeo demo 2 min: guion + storyboard (Lía). Iteración de docs según test de usabilidad.
- **S7 (30 nov–6 dic):** Revisión cruzada de submission. Vídeo editado con subtítulos ES/EN. Pulido de README y repo.
- **S8 (7–13 dic):** **HITO: submission candidata.** Revisión legal final. Congelación de contenidos.
- **S9 (14–20 dic):** BUFFER de imprevistos (1ª semana de colchón). Si todo va bien: adelantar Fase 2 (hardening del modo coacción).
- **S10 (21–27 dic):** BUFFER final + envío de la idea. **No dejar para el día 28.** Objetivo interno: enviar el 21-dic.
- **28-dic-2026 23:59:** deadline oficial (hora peninsular).

## Hitos Fase 2 (orientativos, se refinan si nos seleccionan)
- 29-dic→13-ene: implementación del modo coacción según spec de Lía.
- 14-ene→27-ene: multiplataforma pulida (Win/macOS/Linux), autodestrucción, tests E2E.
- 28-ene→10-feb: builds reproducibles verificados externamente, docs finales, release v1.0.0. **10-feb: MVP entregado.**

## Dependencias críticas (grafo)
spike → spec técnica → prototipo E2E; spike → repo+CI; design system → mockups → test usabilidad y vídeo; investigación usuarios → diseño coacción; propuesta valor + investigación + spec → submission; mockups → vídeo.
**Camino crítico:** spike → spec → prototipo → demo. Cualquier retraso en el spike de Marco come buffer directamente.

## Buffers
- 2 semanas de buffer explícito en Fase 1 (S9–S10), más envío interno adelantado al 21-dic.
- Regla: si una tarea del camino crítico se desvía >3 días, Sara replanifica y, si afecta al envío, escala a Miguel Ángel con opciones.

## Capacidad
4 agentes × 2 slots de autoplay. Carga Fase 1: Marco 5 tareas, Vera 5, Lía 4, Sara 3 (+coordinación recurrente). Nadie sin trabajo: regla de oro <24h.
