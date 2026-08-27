create table if not exists public.insurance_semantic_recovery_memories (
  id uuid primary key default gen_random_uuid(),
  semantic_signature text not null unique,
  semantic_request jsonb not null default '{}'::jsonb,
  verified_entity_ids uuid[] not null default '{}',
  source_concepts text[] not null default '{}',
  expansion_concepts text[] not null default '{}',
  relationship_direction text not null default 'unknown'
    check (relationship_direction in ('forward', 'reverse', 'bidirectional', 'aggregation', 'unknown')),
  retrieval_hypotheses jsonb not null default '[]'::jsonb,
  evidence_ids uuid[] not null default '{}',
  document_snapshots jsonb not null default '[]'::jsonb,
  relation_snapshot jsonb not null default '[]'::jsonb,
  source_audit_id uuid references public.insurance_answer_audits(id) on delete set null,
  confidence numeric(4,3) not null default 0.850 check (confidence between 0 and 1),
  successful_uses integer not null default 0 check (successful_uses >= 0),
  positive_feedback_count integer not null default 0 check (positive_feedback_count >= 0),
  negative_feedback_count integer not null default 0 check (negative_feedback_count >= 0),
  active boolean not null default true,
  last_verified_at timestamptz not null default now(),
  invalidated_at timestamptz,
  invalidation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists insurance_semantic_recovery_memories_active_updated_idx
  on public.insurance_semantic_recovery_memories (updated_at desc)
  where active = true and confidence >= 0.800;

create index if not exists insurance_semantic_recovery_memories_entity_ids_idx
  on public.insurance_semantic_recovery_memories using gin (verified_entity_ids)
  where active = true;

alter table public.insurance_semantic_recovery_memories enable row level security;
revoke all on table public.insurance_semantic_recovery_memories from anon, authenticated;
grant all on table public.insurance_semantic_recovery_memories to service_role;

comment on table public.insurance_semantic_recovery_memories is
  'Verified retrieval-repair memory only. Stores no policy answer or policy fact.';
