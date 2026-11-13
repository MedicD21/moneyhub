export default function SetupError({ message }: { message: string }) {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-bg px-4 py-10">
      <div role="alert" className="glass w-full min-w-0 max-w-lg rounded-[24px] p-6" data-tone="danger">
        <h1 className="text-lg font-semibold text-danger">Money Hub isn’t configured</h1>
        <p className="mt-2 text-sm break-words text-ink">{message}</p>
        <p className="mt-4 text-sm text-muted">Set these environment variables, then restart the dev server or redeploy:</p>
        <pre className="mt-2 overflow-x-auto rounded-lg bg-surface-2 p-3 text-xs text-ink">
          {`VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon or publishable key>`}
        </pre>
        <p className="mt-4 text-sm text-muted">
          Locally, copy <code className="rounded bg-surface-2 px-1">web/.env.example</code> to{' '}
          <code className="rounded bg-surface-2 px-1">web/.env.local</code>. On Vercel, add them under Project Settings → Environment
          Variables. Vite inlines them at build time, so redeploy after changing them.
        </p>
      </div>
    </div>
  );
}
