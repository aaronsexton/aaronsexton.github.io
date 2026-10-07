interface ImportMetaEnv {
  readonly PUBLIC_SUPABASE_URL: string;
  readonly PUBLIC_TURNSTILE_SITE_KEY: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

interface Window {
  turnstile?: {
    reset: (widget?: string | HTMLElement) => void;
  };
}
