# Nido Bebé · Web propia + sistema de gestión

Demos navegables de la propuesta para NIDO BEBÉ (Rosario). Se abren directo en el navegador, sin instalar nada.

| Archivo | Qué es |
|---|---|
| `index.html` | Portada: las dos propuestas, cómo probar, costos y fases |
| `esquema-A-simple.html` | **Esquema A:** web propia + panel (pedidos, etiquetas, stock, historial, dashboard, promos) |
| `esquema-B-integral.html` | **Esquema B:** todo lo de A + bandeja WhatsApp/Instagram, asistente IA, CRM y producción |
| `db/schema.sql` | Estructura de la base de datos real (PostgreSQL / Supabase) que usan los dos esquemas |

## Cómo verlo

- **En línea:** abrir el link de GitHub Pages del repositorio.
- **En la compu:** descargar el repositorio y abrir `index.html` con doble clic.

## Importante

- Son **prototipos**: los pedidos, clientes y números son de ejemplo y se reinician al recargar.
- Los precios y descripciones salen del catálogo 2026. Las **recetas de insumos son estimaciones** que hay que validar con el taller.
- En el sistema real, todo se guarda en la base de datos de `db/schema.sql`, con usuarios, respaldo diario e historial de cada movimiento de stock.

## Próximos pasos

1. Cargar productos, variantes y recetas reales.
2. Publicar la web con fotos profesionales y dominio propio.
3. Construir el panel sobre la base de datos.
4. Sumar el Esquema B (WhatsApp oficial, IA y CRM) cuando el volumen lo pida.
