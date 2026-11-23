"""Build a guarded, mechanical refactor from the installed supply definitions.

All business expressions are retained. A call-local model travels alongside the
unchanged payload; it is never shared between products, requests or snapshots.
"""
import hashlib
import re

SCHEMA = 'stock_management_private.'
RESULT_TYPE = SCHEMA + 'supply_enrichment_result'
NAMES = ('enrich_supply_reconciled', 'enrich_supply', 'resolve_receipt_return', 'analyze_supply')


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Expected one rewrite site: ' + old[:100])
    return text.replace(old, new, 1)


def return_payload(body, model, expected=3):
    pattern = re.compile(r'\breturn\s+(.+?);', re.I | re.S)
    matches = list(pattern.finditer(body))
    if len(matches) != expected:
        raise ValueError('Unexpected supply return structure')
    return pattern.sub(lambda m: 'return (' + m[1] + ', ' + model +
                       ')::' + RESULT_TYPE + ';', body)


def definition(original, body, *, cached=False, paired=False):
    result = replace_once(original['definition'], original['prosrc'], body)
    if cached:
        name = original['proname']
        result = replace_once(result, 'FUNCTION ' + SCHEMA + name + '(p jsonb, evidence jsonb)',
                              'FUNCTION ' + SCHEMA + name + '_cached(p jsonb, evidence jsonb, p_model jsonb)')
    if paired:
        result = replace_once(result, 'RETURNS jsonb', 'RETURNS ' + RESULT_TYPE)
    return result.rstrip().removesuffix(';') + ';\n'


def build(originals):
    source = {f['proname']: f for f in originals}
    for name in (*NAMES, 'fit_supply_demand'):
        if source[name]['provolatile'] != 'i' or source[name]['prosecdef']:
            raise ValueError('Expected immutable invoker-only supply function: ' + name)
    original = source['enrich_supply_reconciled']
    reconciled = replace_once(original['prosrc'],
        'model:=stock_management_private.fit_supply_demand(p);',
        'model:=coalesce(p_model,stock_management_private.fit_supply_demand(p));')
    cached_reconciled = definition(original, reconciled, cached=True)

    original = source['enrich_supply']
    enriched = replace_once(original['prosrc'], 'declare result jsonb;',
                             'declare result jsonb; cached_model jsonb:=p_model;')
    enriched = replace_once(enriched,
        'result:=stock_management_private.enrich_supply_reconciled(p,evidence);',
        'result:=stock_management_private.enrich_supply_reconciled_cached(p,evidence,cached_model);\n'
        "  cached_model:=coalesce(cached_model,result#>'{detail,effective_supply,model}');")
    enriched = replace_once(enriched,
        'chart_result:=stock_management_private.enrich_supply_reconciled(p,\n'
        '      jsonb_set(evidence,\'{summary,confidence}\',\'"inferred"\'));',
        'chart_result:=stock_management_private.enrich_supply_reconciled_cached(p,\n'
        '      jsonb_set(evidence,\'{summary,confidence}\',\'"inferred"\'),cached_model);\n'
        "    cached_model:=coalesce(cached_model,chart_result#>'{detail,effective_supply,model}');")
    enriched = return_payload(enriched, 'cached_model')
    cached_enriched = definition(original, enriched, cached=True, paired=True)

    original = source['resolve_receipt_return']
    resolved = replace_once(original['prosrc'],
        "result:=stock_management_private.enrich_supply(p,jsonb_build_object('summary',s,'detail',detail));",
        "result:=(stock_management_private.enrich_supply_cached(\n"
        "    p,jsonb_build_object('summary',s,'detail',detail),p_model)).payload;")
    cached_resolved = definition(original, resolved, cached=True)

    wrappers = []
    for name in NAMES[:3]:
        if name in ('resolve_receipt_return','enrich_supply_reconciled'):
            body = '\nbegin\n  return stock_management_private.' + name + '_cached(p,evidence,null);\nend;\n'
        else:
            body = '\nbegin\n  return (stock_management_private.' + name + '_cached(p,evidence,null)).payload;\nend;\n'
        wrappers.append(definition(source[name], body))

    original = source['analyze_supply']
    analyzed = replace_once(original['prosrc'], 'declare\n', 'declare\n  enriched ' + RESULT_TYPE + ';\n')
    analyzed = replace_once(analyzed,
        "return stock_management_private.resolve_receipt_return(p,stock_management_private.enrich_supply(p,jsonb_build_object('summary',summary,'detail',result)));",
        "enriched:=stock_management_private.enrich_supply_cached(\n"
        "    p,jsonb_build_object('summary',summary,'detail',result),null);\n"
        "  return stock_management_private.resolve_receipt_return_cached(p,enriched.payload,enriched.demand_model);")
    wrappers.append(definition(original, analyzed))

    guards = []
    for name in (*NAMES, 'fit_supply_demand'):
        digest = hashlib.md5(source[name]['prosrc'].replace('\r\n', '\n').encode()).hexdigest()
        guards.append("    ('" + source[name]['signature'] + "','" + digest + "')")
    guard = '''-- Reuse only the immutable demand model for the exact same product input.
-- All existing JSON expressions, ordering, guards, precision and privileges remain.
-- Fail closed if a business function changed since this refactor was reviewed.
set local lock_timeout='2s';
do $guard$
declare expected record; actual text;
begin
  if to_regtype('stock_management_private.supply_enrichment_result') is not null then
    raise exception 'Supply result type already exists; review required';
  end if;
  if to_regprocedure('stock_management_private.enrich_supply_cached(jsonb,jsonb,jsonb)') is not null
    or to_regprocedure('stock_management_private.enrich_supply_reconciled_cached(jsonb,jsonb,jsonb)') is not null
    or to_regprocedure('stock_management_private.resolve_receipt_return_cached(jsonb,jsonb,jsonb)') is not null then
    raise exception 'Supply cached helper already exists; review required';
  end if;
  for expected in select * from (values
''' + ',\n'.join(guards) + ''') as v(signature,body_hash) loop
    select md5(replace(prosrc,E'\\r\\n',E'\\n')) into actual
    from pg_proc where oid=to_regprocedure(expected.signature);
    if actual is distinct from expected.body_hash then
      raise exception 'Supply definition changed; review required: %',expected.signature;
    end if;
  end loop;
end;
$guard$;
'''
    privileges = '\n'.join(
        'revoke all on function ' + SCHEMA + name + '_cached(jsonb,jsonb,jsonb) from public,anon,authenticated;\n'
        'grant execute on function ' + SCHEMA + name + '_cached(jsonb,jsonb,jsonb) to service_role;'
        for name in NAMES[:3])
    result_type = 'create type ' + RESULT_TYPE + ' as (payload jsonb,demand_model jsonb);\n'
    type_privileges = 'revoke all on type ' + RESULT_TYPE + ' from public,anon,authenticated;\n'
    type_privileges += 'grant usage on type ' + RESULT_TYPE + ' to service_role;\n'
    return guard + '\n' + result_type + '\n' + '\n'.join([cached_reconciled,cached_enriched,cached_resolved,*wrappers]) + '\n' + privileges + '\n' + type_privileges
