-- AlertaBGA · Extensiones y tipos enumerados
create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create type public.incident_status as enum (
  'RECIBIDO', 'EN_REVISION', 'ASIGNADO', 'EN_ATENCION', 'CERRADO', 'NO_PROCEDE'
);

-- RB-01: un reporte ciudadano no equivale a un delito confirmado
create type public.verification_level as enum (
  'REPORTE_CIUDADANO', 'CASO_VERIFICADO', 'DELITO_CONFIRMADO'
);

create type public.report_source as enum (
  'APP_AUTENTICADO', 'APP_ANONIMO', 'INSTITUCIONAL'
);

-- Prioridad sugerida: apoyo a la decisión, no orden de despliegue (RB-09)
create type public.incident_priority as enum ('BAJA', 'MEDIA', 'ALTA', 'CRITICA');

create type public.evidence_status as enum ('PENDIENTE', 'CONFIRMADA', 'RECHAZADA');
