# Local Ollama assistant test

This mode changes only the Flutter assistant endpoint. Flutter authentication,
database reads, RLS, and document evidence remain on the configured Supabase
project. The local Edge Function calls Ollama for structured NLU only; it never
sends source documents to Ollama and never lets Ollama author a final answer.
If the local Edge runtime does not expose Supabase's hosted embedding service,
the same function uses the existing exact/FTS/trigram retrieval path for this
local test rather than failing. Hosted production behavior is unchanged.

1. Start Ollama: `D:\CAIOllama\ollama.exe serve`.
2. Install/initialize the Supabase CLI once: `npx supabase init`.
3. Create the ignored local Edge and Flutter environment files with
   `powershell -ExecutionPolicy Bypass -File .\tools\prepare_local_ollama_env.ps1`.
   It reads the existing ignored `.env` file without printing its values. If
   that file does not contain the two public Supabase values, pass
   `-SupabaseUrl` and `-SupabaseAnonKey` explicitly.
   The script queries `/api/tags`, prefers `qwen3.5:4b` when installed, or
   prints the installed model it selected.
4. Serve only the local function:
   `npx supabase functions serve insurance-assistant --no-verify-jwt --env-file .\supabase\functions\.env.local`.
5. Run Flutter with the generated local configuration:
   `flutter run -d chrome --web-port 54882 --dart-define-from-file=local_development/flutter.local.json`.

Keep the Ollama and local Edge Function terminals open. Look for `[Local LLM]`
messages in the function terminal. A successful request logs URL, model,
request start, and response timing without logging question, policy, or token.
`LOCAL_NLU_REQUIRED=true` makes a stopped/misconfigured Ollama instance return
a clear local-development error instead of silently using the fallback parser.
