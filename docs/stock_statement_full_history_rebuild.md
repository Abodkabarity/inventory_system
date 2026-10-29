# Full Stock Statement history and resume

The monitor downloads APG and 71 statements month by month with SalesType `0`
(ERP label: `All`). It retains all source rows, modes and transaction types,
including `Trans No` as text. It does not filter branches, group repeated lines,
or change quantity signs. Raw names are used for database identities.

Start or resume the existing October 21 job:

```powershell
python automation/stock_statement_full_history_monitor.py --output outputs/stock-statement-full-20261021 --batch-size 100000 --start
```

The default for a new job is 5,000. The user's selected 100,000-row size is saved
in the manifest and shown in the window. Actual data transfer uses direct
PostgreSQL COPY, not a 100,000-row REST/RPC request.

`stk_statement_history_load_progress` is the authoritative resume cursor for
each company and requested month. Each batch's rows and its committed row
number/quantity sum are saved in the same database transaction. Local JSON
progress updates follow COMMIT. A lost acknowledgement cannot advance or erase
the server cursor. Resume checks the original source hash and the database
count/sum, then skips the committed source prefix. A conflicting source or
changed target stops for review instead of silently restarting the month.

Incomplete batches roll back; earlier committed batches remain. Transient
connection failures reconnect and resume up to four attempts. After a terminal
failure or application restart, Start / Resume continues the same saved job.
No resume path executes TRUNCATE or DELETE. Keep the output folder and its
source workbooks/receipts; they identify the exact original source snapshot.

Monthly completion requires matching row count, quantity sum, IN/OUT counts,
and source fingerprints. Repeated identical lines remain separate because the
fingerprint includes the original source row ordinal.

The earlier filtered daily archive cron job 135 was paused for this rebuild and
remains paused pending review. Existing live `stk_statement` loaders still use
their earlier filters; do not resume that archive job against the full-history
table without updating its source/identity strategy.
