-- =====================================================================
-- NIDO BEBÉ · Base de datos central (PostgreSQL / Supabase)
-- Misma base para Esquema A y B: B solo agrega módulos (leads, mensajes).
-- Principio clave: el stock NUNCA se edita a mano, se calcula sumando
-- movimientos. Así siempre hay historial y no se "pierde" mercadería.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------- Catálogo ----------
create table lineas (
  id          smallserial primary key,
  nombre      text not null unique,          -- Juegos, Cumpis, Crea, Deco, Boxs, Baby
  orden       smallint not null default 0
);

create table productos (
  id                  uuid primary key default gen_random_uuid(),
  sku                 text not null unique,  -- ej: JUE-COCINA
  nombre              text not null,
  slug                text not null unique,  -- url de la web
  linea_id            smallint not null references lineas(id),
  descripcion         text,
  medidas             text,
  precio_transferencia numeric(12,2) not null check (precio_transferencia >= 0),
  precio_cuotas       numeric(12,2) not null check (precio_cuotas >= 0),
  precio_por_unidad   text,                  -- ej: 'letra' para guirnaldas
  dias_produccion     smallint not null default 3,
  hecho_a_pedido      boolean not null default true,
  personalizable      boolean not null default false,
  stock_minimo        integer not null default 0,  -- producto terminado
  activo              boolean not null default true,
  destacado           boolean not null default false,
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now()
);

create table producto_imagenes (
  id          uuid primary key default gen_random_uuid(),
  producto_id uuid not null references productos(id) on delete cascade,
  url         text not null,
  orden       smallint not null default 0
);

-- Variantes: animal del velador, color de tusor, tipo de bolsa de dormir…
create table variantes (
  id               uuid primary key default gen_random_uuid(),
  producto_id      uuid not null references productos(id) on delete cascade,
  nombre           text not null,             -- 'León', 'Corderito con tusor'
  ajuste_precio    numeric(12,2) not null default 0,
  activo           boolean not null default true,
  unique (producto_id, nombre)
);

-- ---------- Insumos y recetas ----------
create table proveedores (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,
  whatsapp      text,
  email         text,
  dias_entrega  smallint not null default 3,
  notas         text
);

create table insumos (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique,        -- F9, TUSOR, HILO…
  nombre         text not null,
  unidad         text not null,               -- plancha, m, L, kg, ovillo, u
  costo_unitario numeric(12,2) not null default 0,
  stock_minimo   numeric(12,3) not null default 0,
  proveedor_id   uuid references proveedores(id),
  activo         boolean not null default true
);

-- Receta (lista de materiales): cuánto insumo lleva cada producto
create table recetas (
  producto_id  uuid not null references productos(id) on delete cascade,
  variante_id  uuid references variantes(id) on delete cascade, -- null = aplica a todas
  insumo_id    uuid not null references insumos(id),
  cantidad     numeric(12,3) not null check (cantidad > 0),
  unique nulls not distinct (producto_id, variante_id, insumo_id)
);

-- ---------- Movimientos de stock (historial) ----------
create type tipo_mov as enum ('compra','consumo_produccion','ajuste','produccion_terminada','venta','devolucion');

create table movimientos_stock (
  id           bigserial primary key,
  fecha        timestamptz not null default now(),
  tipo         tipo_mov not null,
  insumo_id    uuid references insumos(id),
  producto_id  uuid references productos(id),
  variante_id  uuid references variantes(id),
  cantidad     numeric(12,3) not null,        -- + entra / - sale
  referencia   text,                          -- 'OP-120', 'PED-1024', 'Compra #8'
  usuario_id   uuid,                          -- quién lo hizo (auth.users)
  nota         text,
  check ((insumo_id is null) <> (producto_id is null))  -- o insumo o producto
);
create index on movimientos_stock (insumo_id);
create index on movimientos_stock (producto_id);

-- ---------- Clientes y pedidos ----------
create table clientes (
  id             uuid primary key default gen_random_uuid(),
  nombre         text not null,
  whatsapp       text unique,
  email          text,
  instagram      text,
  ciudad         text,
  direccion      text,
  fecha_nac_bebe date,                        -- para campañas por edad
  origen         text,                        -- web, wa, ig, feria, referido
  notas          text,
  creado_en      timestamptz not null default now()
);

create type estado_pedido as enum ('nuevo','esperando_pago','sena_pagada','pagado','en_produccion','listo','enviado','entregado','cancelado');
create type medio_pago as enum ('transferencia','cuotas','efectivo');
create type tipo_entrega as enum ('retiro','envio');

create table pedidos (
  id             uuid primary key default gen_random_uuid(),
  numero         serial unique,               -- PED-1024
  cliente_id     uuid not null references clientes(id),
  canal          text not null default 'web', -- web, wa, ig
  estado         estado_pedido not null default 'nuevo',
  medio_pago     medio_pago not null,
  entrega        tipo_entrega not null default 'retiro',
  direccion_envio text,
  costo_envio    numeric(12,2) not null default 0,
  total          numeric(12,2) not null default 0,
  fecha_entrega  date,                        -- comprometida al cliente
  notas          text,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create index on pedidos (estado);

create table pedido_items (
  id               uuid primary key default gen_random_uuid(),
  pedido_id        uuid not null references pedidos(id) on delete cascade,
  producto_id      uuid not null references productos(id),
  variante_id      uuid references variantes(id),
  cantidad         integer not null check (cantidad > 0),
  precio_unitario  numeric(12,2) not null,    -- precio congelado al momento de la venta
  personalizacion  text                       -- 'EMMA, tonos verdes'
);

create table pagos (
  id           uuid primary key default gen_random_uuid(),
  pedido_id    uuid not null references pedidos(id) on delete cascade,
  monto        numeric(12,2) not null check (monto > 0),
  medio        medio_pago not null,
  comprobante_url text,
  confirmado   boolean not null default false,
  fecha        timestamptz not null default now()
);

-- ---------- Producción ----------
create type estado_op as enum ('pendiente','corte','confeccion_pintura','terminacion','terminado','cancelado');

create table ordenes_produccion (
  id             uuid primary key default gen_random_uuid(),
  numero         serial unique,               -- OP-120
  pedido_item_id uuid references pedido_items(id), -- null = para stock
  producto_id    uuid not null references productos(id),
  variante_id    uuid references variantes(id),
  cantidad       integer not null check (cantidad > 0),
  estado         estado_op not null default 'pendiente',
  fecha_limite   date,
  responsable    text,
  creado_en      timestamptz not null default now(),
  terminado_en   timestamptz
);

-- ---------- Compras a proveedores ----------
create table compras (
  id            uuid primary key default gen_random_uuid(),
  proveedor_id  uuid references proveedores(id),
  estado        text not null default 'borrador', -- borrador, enviada, recibida
  total         numeric(12,2) not null default 0,
  creado_en     timestamptz not null default now()
);
create table compra_items (
  compra_id  uuid not null references compras(id) on delete cascade,
  insumo_id  uuid not null references insumos(id),
  cantidad   numeric(12,3) not null,
  costo_unitario numeric(12,2) not null,
  primary key (compra_id, insumo_id)
);

-- ---------- Alertas ----------
create table alertas (
  id         bigserial primary key,
  tipo       text not null,                   -- stock_bajo, pedido_demorado, sin_pago, lead_sin_respuesta
  mensaje    text not null,
  referencia text,
  resuelta   boolean not null default false,
  creado_en  timestamptz not null default now()
);

-- =====================================================================
-- Módulos del ESQUEMA B (CRM: leads + bandeja de WhatsApp/Instagram)
-- =====================================================================
create type etapa_lead as enum ('nuevo','cotizado','sena','produccion','listo','entregado','perdido');

create table leads (
  id           uuid primary key default gen_random_uuid(),
  cliente_id   uuid not null references clientes(id),
  canal        text not null,                 -- wa, ig, web
  etapa        etapa_lead not null default 'nuevo',
  producto_interes_id uuid references productos(id),
  valor_estimado numeric(12,2),
  pedido_id    uuid references pedidos(id),   -- cuando se convierte
  proximo_seguimiento timestamptz,
  creado_en    timestamptz not null default now()
);

create table mensajes (
  id          bigserial primary key,
  cliente_id  uuid not null references clientes(id),
  canal       text not null,                  -- wa, ig
  direccion   text not null check (direccion in ('entrante','saliente')),
  autor       text not null default 'cliente', -- cliente, ia, humano
  texto       text,
  media_url   text,
  externo_id  text unique,                    -- id del mensaje en Meta
  fecha       timestamptz not null default now()
);
create index on mensajes (cliente_id, fecha);

-- =====================================================================
-- Vistas: stock calculado + dashboard
-- =====================================================================
create view v_stock_insumos as
select i.id, i.codigo, i.nombre, i.unidad, i.stock_minimo, i.costo_unitario,
       coalesce(sum(m.cantidad),0) as stock,
       case when coalesce(sum(m.cantidad),0) < i.stock_minimo * 0.5 then 'critico'
            when coalesce(sum(m.cantidad),0) < i.stock_minimo       then 'reponer'
            else 'ok' end as estado
from insumos i
left join movimientos_stock m on m.insumo_id = i.id
where i.activo
group by i.id;

create view v_stock_productos as
select p.id, p.sku, p.nombre, p.stock_minimo,
       coalesce(sum(m.cantidad),0) as stock
from productos p
left join movimientos_stock m on m.producto_id = p.id
group by p.id;

create view v_margen_productos as
select p.id, p.nombre, p.precio_transferencia,
       coalesce(sum(r.cantidad * i.costo_unitario),0) as costo_insumos,
       p.precio_transferencia - coalesce(sum(r.cantidad * i.costo_unitario),0) as margen
from productos p
left join recetas r on r.producto_id = p.id and r.variante_id is null
left join insumos i on i.id = r.insumo_id
group by p.id;

-- =====================================================================
-- Automatismo central: al crear una orden de producción se descuentan
-- los insumos de su receta y, si alguno baja del mínimo, se crea alerta.
-- =====================================================================
create or replace function fn_consumir_insumos() returns trigger as $$
declare r record;
begin
  insert into movimientos_stock (tipo, insumo_id, cantidad, referencia)
  select 'consumo_produccion', rc.insumo_id, -(rc.cantidad * new.cantidad), 'OP-' || new.numero
  from recetas rc
  where rc.producto_id = new.producto_id
    and (rc.variante_id is null or rc.variante_id = new.variante_id);

  for r in select * from v_stock_insumos where estado <> 'ok' loop
    insert into alertas (tipo, mensaje, referencia)
    select 'stock_bajo', r.nombre || ': quedan ' || r.stock || ' ' || r.unidad || ' (mínimo ' || r.stock_minimo || ')', r.codigo
    where not exists (select 1 from alertas a where a.referencia = r.codigo and a.tipo = 'stock_bajo' and not a.resuelta);
  end loop;
  return new;
end $$ language plpgsql;

create trigger trg_op_consumo after insert on ordenes_produccion
for each row execute function fn_consumir_insumos();

-- Al terminar una OP sin pedido (para stock) entra producto terminado
create or replace function fn_op_terminada() returns trigger as $$
begin
  if new.estado = 'terminado' and old.estado <> 'terminado' then
    new.terminado_en := now();
    if new.pedido_item_id is null then
      insert into movimientos_stock (tipo, producto_id, variante_id, cantidad, referencia)
      values ('produccion_terminada', new.producto_id, new.variante_id, new.cantidad, 'OP-' || new.numero);
    end if;
  end if;
  return new;
end $$ language plpgsql;

create trigger trg_op_terminada before update on ordenes_produccion
for each row execute function fn_op_terminada();

-- =====================================================================
-- Seguridad (Row Level Security): la web pública solo LEE el catálogo
-- activo; todo lo demás requiere usuario logueado del panel.
-- =====================================================================
alter table productos          enable row level security;
alter table producto_imagenes  enable row level security;
alter table variantes          enable row level security;
alter table lineas             enable row level security;

create policy catalogo_publico on productos         for select using (activo);
create policy imagenes_publico on producto_imagenes for select using (true);
create policy variantes_publico on variantes        for select using (activo);
create policy lineas_publico   on lineas            for select using (true);

-- Resto de las tablas: cerradas al público, abiertas solo al equipo logueado
do $$
declare t text;
begin
  foreach t in array array['proveedores','insumos','recetas','movimientos_stock','clientes',
    'pedidos','pedido_items','pagos','ordenes_produccion','compras','compra_items',
    'alertas','leads','mensajes'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy equipo_%s on %I for all to authenticated using (true) with check (true)', t, t);
  end loop;
  -- el equipo también puede editar el catálogo
  foreach t in array array['productos','producto_imagenes','variantes','lineas'] loop
    execute format('create policy equipo_%s on %I for all to authenticated using (true) with check (true)', t, t);
  end loop;
end $$;

-- Los pedidos desde la web entran por una función del servidor (Edge Function)
-- que valida datos y precios: el navegador nunca escribe directo en la base.
