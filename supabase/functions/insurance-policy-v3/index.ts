import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { answerFromEvidence, GROQ_MODEL, interpretQuestion } from './groq.ts';
import {
  chunkAnswersDimension, enforceRouteSafety, evidenceForAnswer, normalize, requestedDimensions,
  isolateMedicationCandidates, rerankChunks, resolveVerifiedEntities, selectEvidence,
  type V3Alias, type V3Chunk, type V3Entity, type V3Relation,
} from './retrieval.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function respond(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

function usageTotal(usage: unknown) {
  if (!usage || typeof usage !== 'object') return 0;
  const value = (usage as Record<string, unknown>).total_tokens;
  return typeof value === 'number' ? value : 0;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const started = Date.now();
  try {
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return respond({ error: 'Authentication required.' }, 401);
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authorization } }, auth: { persistSession: false },
    });
    const { data: auth, error: authError } = await db.auth.getUser(authorization.slice(7));
    if (authError || !auth.user) return respond({ error: 'Authentication required.' }, 401);
    const body = await request.json() as Record<string, unknown>;
    const question = String(body.message ?? '').trim();
    if (!question || question.length > 1200) return respond({ error: 'A question of at most 1200 characters is required.' }, 400);

    const semanticResult = await interpretQuestion(question);
    const [{ data: entities, error: entityError }, { data: aliases, error: aliasError }, { data: relations, error: relationError }] = await Promise.all([
      db.from('insurance_v3_entities').select('id,canonical_name,normalized_name,entity_type').eq('active', true),
      db.from('insurance_v3_aliases').select('entity_id,alias,normalized_alias,verified').eq('verified', true),
      db.from('insurance_v3_entity_relations').select('subject_entity_id,relation_type,object_entity_id,verified').eq('verified', true),
    ]);
    if (entityError || aliasError || relationError) throw entityError ?? aliasError ?? relationError;
    const verifiedEntities = resolveVerifiedEntities(question, semanticResult.semantic, entities as V3Entity[], aliases as V3Alias[], relations as V3Relation[]);
    const dimensions = requestedDimensions(question, semanticResult.semantic);
    const semantic = enforceRouteSafety(semanticResult.semantic, verifiedEntities, dimensions);

    if (semantic.route === 'out_of_scope' || semantic.route === 'clarification_required') {
      return respond({ answer: semantic.route === 'out_of_scope' ? 'This question is outside the approved insurance-policy knowledge base.' : 'Please clarify the medication or policy criterion you want to check.', citations: [], answer_status: semantic.route, insurance_v3: true, debug: body.debug === true ? { semantic_interpretation: semantic, semantic_usage: semanticResult.usage, groq: { semantic_tokens: semanticResult.usage, answer_tokens: null, total_tokens: usageTotal(semanticResult.usage) } } : undefined });
    }

    const searchParts = [question, ...verifiedEntities.map((entity) => entity.canonical_name), semantic.indication, ...dimensions, ...semantic.facts.flatMap((fact) => [fact.concept, fact.value, fact.unit, fact.temporal])].filter((value) => value !== null && value !== undefined && String(value).trim());
    const { data: firstRows, error: searchError } = await db.rpc('insurance_v3_search', {
      p_query: searchParts.join(' '), p_entity_ids: verifiedEntities.map((entity) => entity.id),
      p_dimensions: dimensions, p_stage: semantic.treatment_stage, p_document_ids: [], p_limit: 30,
    });
    if (searchError) throw searchError;
    const firstCandidates = (firstRows ?? []) as V3Chunk[];
    const entityScopedFirst = isolateMedicationCandidates(
      verifiedEntities.length > 0
        ? firstCandidates.filter((chunk) => chunk.matched_entity_count > 0)
        : firstCandidates,
      verifiedEntities,
    );
    let candidates = rerankChunks(entityScopedFirst, verifiedEntities, dimensions, semantic.treatment_stage, question);
    let selection = selectEvidence(candidates, dimensions, 6);
    let retrievalExpanded = false;
    if (selection.missingDimensions.length > 0) {
      const constrainedDocuments = [...new Set(candidates.filter((chunk) => chunk.matched_entity_count > 0).map((chunk) => chunk.document_id))];
      if (constrainedDocuments.length > 0) {
        const { data: secondRows, error: secondError } = await db.rpc('insurance_v3_search', {
          p_query: `${searchParts.join(' ')} ${selection.missingDimensions.join(' ')}`,
          p_entity_ids: verifiedEntities.map((entity) => entity.id), p_dimensions: selection.missingDimensions,
          p_stage: semantic.treatment_stage, p_document_ids: constrainedDocuments, p_limit: 20,
        });
        if (secondError) throw secondError;
        const entityScopedSecond = verifiedEntities.length > 0
          ? ((secondRows ?? []) as V3Chunk[]).filter((chunk) => chunk.matched_entity_count > 0)
          : (secondRows ?? []) as V3Chunk[];
        const secondCandidates = isolateMedicationCandidates(entityScopedSecond, verifiedEntities);
        const byId = new Map([...candidates, ...secondCandidates].map((chunk) => [chunk.chunk_id, chunk]));
        candidates = rerankChunks([...byId.values()], verifiedEntities, dimensions, semantic.treatment_stage, question);
        selection = selectEvidence(candidates, dimensions, 6);
        retrievalExpanded = true;
      }
    }
    if (selection.selected.length === 0) {
      return respond({ answer: 'The approved documents do not establish the answer.', citations: [], answer_status: 'insufficient_evidence', insurance_v3: true, debug: body.debug === true ? { semantic_interpretation: semantic, verified_entities: verifiedEntities, retrieved_chunks: [], retrieval_expanded: retrievalExpanded, missing_dimensions: selection.missingDimensions, groq: { semantic_tokens: semanticResult.usage, answer_tokens: null, total_tokens: usageTotal(semanticResult.usage) }, processing_ms: Date.now() - started } : undefined });
    }

    const answerResult = await answerFromEvidence(question, semantic, selection.selected);
    const used = evidenceForAnswer(selection.selected, answerResult.used_evidence_ids, dimensions);
    const citations = used.map((chunk) => ({
      document_id: chunk.document_id, document_title: chunk.document_title, file_name: chunk.file_name,
      page_from: chunk.page_from, page_to: chunk.page_to, sheet_name: chunk.sheet_name,
      row_from: chunk.row_from, row_to: chunk.row_to, chunk_id: chunk.chunk_id,
    }));
    const sourceLines = [...new Set(used.map((chunk) => chunk.sheet_name
      ? `Source: ${chunk.document_title} — Sheet ${chunk.sheet_name}, rows ${chunk.row_from ?? '?'}-${chunk.row_to ?? '?'}`
      : `Source: ${chunk.document_title} — Page ${chunk.page_from}${chunk.page_to !== chunk.page_from ? `-${chunk.page_to}` : ''}`))];
    const answer = `${answerResult.answer.replace(/\n*Source:\s*[\s\S]*$/i, '').trim()}\n\n${sourceLines.join('\n')}`;

    let sessionId = typeof body.session_id === 'string' ? body.session_id : null;
    if (!sessionId) {
      const { data: session, error } = await db.from('insurance_chat_sessions').insert({ branch_name: String(body.branch_name ?? ''), title: question.slice(0, 80) }).select('id').single();
      if (error) throw error; sessionId = session.id;
    }
    const parsed = { insurance_v3: true, semantic, verified_entity_ids: verifiedEntities.map((entity) => entity.id) };
    const { error: userError } = await db.from('insurance_chat_messages').insert({ session_id: sessionId, role: 'user', message: question, parsed_data: parsed });
    if (userError) throw userError;
    const { data: assistant, error: assistantError } = await db.from('insurance_chat_messages').insert({ session_id: sessionId, role: 'assistant', message: answer, citations, parsed_data: { ...parsed, answer_status: 'grounded' } }).select('id,created_at').single();
    if (assistantError) throw assistantError;
    const totalTokens = usageTotal(semanticResult.usage) + usageTotal(answerResult.usage);
    return respond({
      session_id: sessionId, message_id: assistant.id, created_at: assistant.created_at,
      answer, citations, confidence: null, answer_status: 'grounded', answer_generator: 'groq', evidence_checked: true, insurance_v3: true,
      debug: body.debug === true ? {
        semantic_interpretation: semantic, verified_entities: verifiedEntities,
        retrieved_chunks: selection.selected.map((chunk) => ({ chunk_id: chunk.chunk_id, document: chunk.document_title, page_from: chunk.page_from, page_to: chunk.page_to, score: chunk.deterministic_score, dimensions: dimensions.filter((dimension) => chunkAnswersDimension(chunk, dimension)), text: chunk.chunk_text })),
        retrieval_expanded: retrievalExpanded, missing_dimensions: selection.missingDimensions,
        groq: { model: GROQ_MODEL, semantic_tokens: semanticResult.usage, answer_tokens: answerResult.usage, total_tokens: totalTokens, semantic_latency_ms: semanticResult.latency_ms, answer_latency_ms: answerResult.latency_ms },
        processing_ms: Date.now() - started,
      } : undefined,
    });
  } catch (error) {
    console.error('insurance_v3_error', { message: error instanceof Error ? error.message : String(error) });
    return respond({ error: error instanceof Error ? error.message : 'Unable to answer the V3 policy question.', insurance_v3: true }, 400);
  }
});
