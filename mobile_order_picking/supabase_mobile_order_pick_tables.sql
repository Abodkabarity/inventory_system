CREATE TABLE IF NOT EXISTS public.mobile_order_pick_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch text NOT NULL,
  movement_date date NOT NULL,
  picker_name text NOT NULL,
  category text NOT NULL,
  status text NOT NULL DEFAULT 'in_progress',
  completed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.mobile_order_pick_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.mobile_order_pick_sessions(id) ON DELETE CASCADE,
  branch text NOT NULL,
  movement_date date NOT NULL,
  category text NOT NULL,
  picker_name text NOT NULL,
  item_code text NOT NULL,
  item_name text NOT NULL,
  expected_qty numeric NOT NULL DEFAULT 0,
  picked_qty numeric NOT NULL DEFAULT 0,
  scanned_barcode text,
  item_barcode text,
  is_matched boolean NOT NULL DEFAULT false,
  source_id text,
  product_movement_id bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mobile_pick_sessions_date_branch
  ON public.mobile_order_pick_sessions (movement_date, branch);

CREATE INDEX IF NOT EXISTS idx_mobile_pick_sessions_completed_at
  ON public.mobile_order_pick_sessions (completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_mobile_pick_results_session
  ON public.mobile_order_pick_results (session_id);

CREATE INDEX IF NOT EXISTS idx_mobile_pick_results_date_branch
  ON public.mobile_order_pick_results (movement_date, branch);

CREATE INDEX IF NOT EXISTS idx_mobile_pick_results_item_code
  ON public.mobile_order_pick_results (item_code);

ALTER TABLE public.mobile_order_pick_sessions
  ALTER COLUMN status SET DEFAULT 'in_progress';

ALTER TABLE public.mobile_order_pick_sessions
  ALTER COLUMN completed_at DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mobile_pick_session
  ON public.mobile_order_pick_sessions (branch, movement_date, picker_name, category);

CREATE UNIQUE INDEX IF NOT EXISTS uq_mobile_pick_result_session_item
  ON public.mobile_order_pick_results (session_id, item_code);

ALTER TABLE public.mobile_order_pick_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mobile_order_pick_results ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mobile_order_pick_sessions_authenticated_select
  ON public.mobile_order_pick_sessions;
CREATE POLICY mobile_order_pick_sessions_authenticated_select
  ON public.mobile_order_pick_sessions
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS mobile_order_pick_sessions_authenticated_insert
  ON public.mobile_order_pick_sessions;
CREATE POLICY mobile_order_pick_sessions_authenticated_insert
  ON public.mobile_order_pick_sessions
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS mobile_order_pick_sessions_authenticated_update
  ON public.mobile_order_pick_sessions;
CREATE POLICY mobile_order_pick_sessions_authenticated_update
  ON public.mobile_order_pick_sessions
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS mobile_order_pick_results_authenticated_select
  ON public.mobile_order_pick_results;
CREATE POLICY mobile_order_pick_results_authenticated_select
  ON public.mobile_order_pick_results
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS mobile_order_pick_results_authenticated_insert
  ON public.mobile_order_pick_results;
CREATE POLICY mobile_order_pick_results_authenticated_insert
  ON public.mobile_order_pick_results
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS mobile_order_pick_results_authenticated_update
  ON public.mobile_order_pick_results;
CREATE POLICY mobile_order_pick_results_authenticated_update
  ON public.mobile_order_pick_results
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
