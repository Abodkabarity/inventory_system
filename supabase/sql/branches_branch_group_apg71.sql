-- Safe branch group classification helper.
-- Keep branch_type untouched because it is already used for Online/Retail.
-- branch_group is optional and can be used for APG/71 style grouping.

ALTER TABLE public.branches
ADD COLUMN IF NOT EXISTS branch_group text;

-- Classify only rows that do not already have a manual group.
-- Branches that contain the word "Branch" are the APG 71 group.
UPDATE public.branches
SET branch_group = '71'
WHERE COALESCE(NULLIF(TRIM(branch_group), ''), '') = ''
  AND branch_name ILIKE '%branch%';

-- Any remaining unclassified branch is APG.
UPDATE public.branches
SET branch_group = 'APG'
WHERE COALESCE(NULLIF(TRIM(branch_group), ''), '') = '';
