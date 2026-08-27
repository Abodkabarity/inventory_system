# Insurance V3 hybrid retrieval rollback

The hybrid semantic search index is additive. The approved V3 source tables and
all V2 tables, functions, and data remain intact.

## Temporarily restore the previous V3 lexical retrieval path

```powershell
supabase secrets set INSURANCE_V3_RETRIEVAL_MODE=lexical --project-ref rzvxjkbraufqbfhvftcy
supabase functions deploy insurance-policy-v3 --project-ref rzvxjkbraufqbfhvftcy
```

This changes only the retrieval feature flag. It does not delete search units,
embeddings, approved V3 evidence, or V2 data.

## Re-enable hybrid retrieval

```powershell
supabase secrets set INSURANCE_V3_RETRIEVAL_MODE=hybrid --project-ref rzvxjkbraufqbfhvftcy
supabase functions deploy insurance-policy-v3 --project-ref rzvxjkbraufqbfhvftcy
```

After either change, issue one authenticated smoke request and verify the
internal diagnostic field `retrieval_mode` reports the intended mode.
