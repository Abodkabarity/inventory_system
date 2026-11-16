create function public.inventory_daily_order_filter_read(p_request jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog
as $function$
declare
  v_types constant jsonb := '{
    "branch":"text","item_code":"text","item_name":"text","barcode":"text",
    "branch_stock":"numeric","mismatch_stock":"numeric","store_stock":"numeric",
    "pending_stock_received":"numeric","extra_qty_more_than_month":"numeric",
    "max_adjustment_30d":"numeric","demand_for_30_days":"numeric",
    "reorder_point_min":"numeric","reorder_max":"numeric","reorder_qty_num":"numeric",
    "final_reorder_qty_store_stock_gt_0":"text","goods_received_last_7_days":"text",
    "date_of_last_qty_received_in_branch":"text","qty_30_days_from_last_45d":"numeric",
    "total_sold_qty_cash_last_90":"numeric","total_sold_qty_online_last_90":"numeric",
    "total_sold_qty_insurance_last_90":"numeric","total_sales_last_90_days":"numeric",
    "branch_formulary":"text","assortment_qty_base_stock":"numeric","assortment_by":"text",
    "reason":"text","assortment_start":"date","assortment_end":"date","tma_qty":"numeric",
    "tma_start":"date","tma_end":"date","item_purchase_type":"text","sales_orientation":"text",
    "category":"text","sub_category":"text","company":"text","supplier":"text",
    "indication":"text","active_ingredient":"text","pack_size":"text","concentration":"text",
    "product_type_form":"text","retail_price":"numeric","vat":"numeric","is_upp":"boolean",
    "item_minimum_order_unit":"numeric","store_item_classifications":"text"
  }';
  v_date date := (p_request->>'run_date')::date;
  v_facet text := p_request->>'facet';
  v_sort text := coalesce(p_request->>'sort', 'item_code');
  v_cursor jsonb := p_request->'cursor';
  v_ascending boolean := coalesce((p_request->>'ascending')::boolean, true);
  v_search text := coalesce(p_request->>'search', '');
  v_lookup text := coalesce(p_request->>'lookup', '');
  v_where text := 'd.run_date = $1';
  v_column text;
  v_type text;
  v_expr text;
  v_blank text;
  v_selection text;
  v_filter jsonb;
  v_rule jsonb;
  v_value text;
  v_pattern text;
  v_op text;
  v_parts text[];
  v_keys text[] := array[]::text[];
  v_order text[] := array[]::text[];
  v_equal text[] := array[]::text[];
  v_after text[] := array[]::text[];
  v_direction text;
  v_projection text;
  v_result jsonb;
begin
  if v_date is null or not (v_types ? v_sort)
     or (v_facet is not null and not (v_types ? v_facet)) then
    raise exception 'Invalid daily order filter request' using errcode = '22023';
  end if;

  if p_request->>'branch' is not null then
    v_where := v_where || format(' and d.branch = %L', p_request->>'branch');
  end if;
  if v_search <> '' then
    v_pattern := '%' || replace(replace(replace(v_search, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';
    v_where := v_where || format(
      ' and (d.item_name ilike %1$L or d.item_code ilike %1$L or d.barcode ilike %1$L or d.branch ilike %1$L',
      v_pattern
    );
    if jsonb_array_length(coalesce(p_request->'branch_matches', '[]')) > 0 then
      v_where := v_where || format(' or lower(d.branch) = any (%L::text[])',
        array(select lower(x) from jsonb_array_elements_text(p_request->'branch_matches') as t(x)));
    end if;
    v_where := v_where || ')';
  end if;

  for v_filter in select value from jsonb_array_elements(coalesce(p_request->'filters', '[]')) loop
    v_column := v_filter->>'column';
    v_type := v_types->>v_column;
    if v_type is null then
      raise exception 'Unsupported daily order filter column' using errcode = '22023';
    end if;
    if v_column = v_facet then continue; end if;

    v_expr := format('d.%I', v_column);
    v_blank := case when v_type = 'text'
      then format('(%1$s is null or %1$s = %2$L)', v_expr, '')
      else v_expr || ' is null'
    end;

    if v_filter ? 'values' then
      v_selection := format(
        '%s = any (%L::%s[])',
        v_expr, array(select x from jsonb_array_elements_text(v_filter->'values') as t(x) where x is not null), v_type
      );
      if (v_filter->'values') @> '[null]'::jsonb then
        v_selection := v_selection || ' or ' || v_blank;
      end if;
      v_where := v_where || case when coalesce((v_filter->>'exclude')::boolean, false)
        then ' and not coalesce((' || v_selection || '), false)'
        else ' and (' || v_selection || ')' end;
      continue;
    end if;

    v_parts := array[]::text[];
    for v_rule in select value from jsonb_array_elements(coalesce(v_filter->'rules', '[]')) loop
      v_op := v_rule->>'operator';
      v_value := v_rule->>'value';
      if v_op in ('isEmpty', 'isNotEmpty') then
        v_selection := case when v_op = 'isEmpty' then v_blank else 'not (' || v_blank || ')' end;
      elsif v_type = 'text' and v_op in ('contains', 'doesNotContain', 'startsWith', 'endsWith', 'equals', 'notEqual') then
        v_pattern := replace(replace(replace(v_value, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_');
        if v_op in ('contains', 'doesNotContain', 'endsWith') then v_pattern := '%' || v_pattern; end if;
        if v_op in ('contains', 'doesNotContain', 'startsWith') then v_pattern := v_pattern || '%'; end if;
        v_selection := format('%s %s ilike %L', v_expr,
          case when v_op in ('doesNotContain', 'notEqual') then 'not' else '' end, v_pattern);
      else
        v_op := case v_op
          when 'equals' then '=' when 'notEqual' then '<>'
          when 'greaterThan' then '>' when 'atLeast' then '>='
          when 'lessThan' then '<' when 'atMost' then '<=' end;
        if v_op is null or v_value is null then
          raise exception 'Unsupported daily order filter rule' using errcode = '22023';
        end if;
        v_selection := format('%s %s %L', v_expr, v_op, v_value);
      end if;
      v_parts := array_append(v_parts, v_selection);
    end loop;
    if cardinality(v_parts) > 0 then
      v_where := v_where || ' and (' || array_to_string(v_parts,
        case when coalesce((v_filter->>'match_any')::boolean, false) then ' or ' else ' and ' end) || ')';
    end if;
  end loop;

  if v_facet is not null then
    v_expr := format('d.%I', v_facet);
    v_type := v_types->>v_facet;
    if v_type = 'text' and v_facet not in ('item_code', 'branch') then
      v_expr := format('nullif(%s, %L)', v_expr, '');
    end if;
    if v_lookup <> '' then
      v_pattern := '%' || replace(replace(replace(v_lookup, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';
      v_parts := array[format('%s::text ilike %L', v_expr, v_pattern)];
      if strpos('(blanks)', lower(v_lookup)) > 0 then
        v_parts := array_append(v_parts, v_expr || ' is null');
      end if;
      if v_facet = 'branch' then
        v_parts := array_append(v_parts, format('lower(d.branch) = any (%L::text[])',
          array(select lower(x) from jsonb_array_elements_text(p_request->'lookup_branches') as t(x))));
      elsif v_type = 'boolean' then
        v_parts := array_append(v_parts, format('(case %s when true then %L when false then %L end) ilike %L',
          v_expr, 'Yes', 'No', v_pattern));
      end if;
      v_where := v_where || ' and (' || array_to_string(v_parts, ' or ') || ')';
    end if;
    if p_request->>'value_after' is not null then
      v_where := v_where || format(' and (%1$s > %2$L or %1$s is null)', v_expr, p_request->>'value_after');
    end if;
    execute format(
      'select coalesce(jsonb_agg(value::text order by value nulls last), %L::jsonb)
       from (select distinct %s as value from public.daily_order d where %s order by value nulls last limit 101) options',
      '[]', v_expr, v_where
    ) into v_result using v_date;
    return v_result;
  end if;

  foreach v_column in array array[v_sort, 'item_code', 'branch'] loop
    if v_column = any(v_keys) then continue; end if;
    v_keys := array_append(v_keys, v_column);
    v_direction := case when v_column = v_sort and not v_ascending then 'desc' else 'asc' end;
    v_order := array_append(v_order, format('%I %s nulls last', v_column, v_direction));
    if v_cursor is null or v_cursor = 'null'::jsonb then continue; end if;
    v_value := v_cursor->>v_column;
    if v_value is null then
      v_equal := array_append(v_equal, format('d.%I is null', v_column));
      continue;
    end if;
    if v_column = v_sort and v_column in ('item_code', 'branch') then
      v_where := v_where || format(' and d.%I %s %L', v_column,
        case when v_direction = 'desc' then '<=' else '>=' end, v_value);
    end if;
    v_selection := format('d.%I %s %L', v_column, case when v_direction = 'desc' then '<' else '>' end, v_value);
    if v_column not in ('item_code', 'branch') then
      v_selection := format('(%s or d.%I is null)', v_selection, v_column);
    end if;
    v_after := array_append(v_after, '(' || array_to_string(array_append(v_equal, v_selection), ' and ') || ')');
    v_equal := array_append(v_equal, format('d.%I = %L', v_column, v_value));
  end loop;
  if cardinality(v_after) > 0 then
    v_where := v_where || ' and (' || array_to_string(v_after, ' or ') || ')';
  end if;
  select string_agg(format('d.%I', key), ', ') into v_projection from jsonb_object_keys(v_types) as t(key);
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(batch) order by %s), %L::jsonb)
     from (select %s from public.daily_order d where %s order by %s limit 121) batch',
    array_to_string(v_order, ', '), '[]', v_projection, v_where, array_to_string(v_order, ', ')
  ) into v_result using v_date;
  return v_result;
end;
$function$;

revoke all on function public.inventory_daily_order_filter_read(jsonb) from public, anon;
grant execute on function public.inventory_daily_order_filter_read(jsonb) to authenticated;
