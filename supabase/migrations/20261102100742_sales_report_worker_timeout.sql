-- PostgREST reads this RPC-scoped setting before executing the worker query.
-- Leave authenticator/service_role and every other feature's timeouts unchanged.
alter function public.sales_report_worker(text,jsonb) set statement_timeout='60s';
notify pgrst,'reload schema';
