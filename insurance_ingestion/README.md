# Insurance document ingestion worker

This private worker preserves the original file in Supabase Storage, extracts PDF/DOCX/XLSX/XLSB structure, creates source-aware chunks, and generates normalized 384-dimensional `gte-small` embeddings locally. The model is intentionally aligned with the query model used by the Edge Function; never mix embedding models in the same index.

```powershell
python -m pip install -r insurance_ingestion/requirements.txt
$env:SUPABASE_URL='https://your-project.supabase.co'
$env:SUPABASE_SERVICE_ROLE_KEY='service-role-key-for-this-worker-only'
python insurance_ingestion/worker.py "C:\guidelines\CGRP.pdf" --category migraine --version 2026
```

To ingest or resume the complete policy folder without duplicating documents:

```powershell
python insurance_ingestion/batch_ingest.py "Summaries of Circulars" --skip-embeddings
python insurance_ingestion/run_remote_embeddings.py
python insurance_ingestion/retrieval_qa.py
```

`batch_ingest.py` uses the source checksum and filename to resume safely. It
marks extracted documents as awaiting embeddings, while the remote embedding
runner processes only missing vectors. The QA script verifies entity resolution,
document scoping, and evidence retrieval across representative policy families.

The default local checkpoint is `thenlper/gte-small`. If it must be overridden,
set `INSURANCE_EMBEDDING_MODEL`, re-embed every document in the same index, and
change the query model at the same time. Do not re-embed only part of the corpus.

The service-role key must never be placed in Flutter, committed to Git, or exposed to a browser. OCR requires a local Tesseract installation with English and Arabic language packs and runs only for pages without usable native text.
