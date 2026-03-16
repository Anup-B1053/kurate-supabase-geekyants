-- ── Profiles ──────────────────────────────────────────────────

CREATE TYPE theme_pref_enum AS ENUM ('light', 'dark', 'auto');

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name TEXT,
  last_name TEXT,
  handle TEXT UNIQUE,
  about TEXT,
  is_onboarded BOOLEAN NOT NULL DEFAULT FALSE,
  avtar_url TEXT,
  xp INTEGER NOT NULL DEFAULT 0,
  theme_pref theme_pref_enum NOT NULL DEFAULT 'light',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_handle ON public.profiles (handle);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can VIEW own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can INSERT own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can UPDATE own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);



-- ── Companions ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.companions (
  user_id uuid PRIMARY KEY NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  stage SMALLINT NOT NULL DEFAULT 1,
  avatar_url text NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);


ALTER TABLE public.companions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can VIEW companions"
  ON public.companions FOR SELECT
  USING (TRUE);

CREATE POLICY "Users can INSERT own companion"
  ON public.companions FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can UPDATE own companion"
  ON public.companions FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);


-- ── Interests ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.interests (
  id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE public.interests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can VIEW interests"
  ON public.interests FOR SELECT
  USING (TRUE);


-- ── User interests ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.user_interests (
  id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  interest_id UUID UNIQUE NOT NULL REFERENCES public.interests(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_interests_user_id ON public.user_interests (user_id);
CREATE INDEX IF NOT EXISTS idx_user_interests_user_id ON public.user_interests (interest_id);

ALTER TABLE public.user_interests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User can can VIEW own interests"
  ON public.user_interests FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can INSERT own interests"
  ON public.user_interests FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can UPDATE own interests"
  ON public.user_interests FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);


-- ── Logged Categories ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.logged_categories (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL UNIQUE,
  slug       TEXT NOT NULL UNIQUE,
  color      TEXT NOT NULL DEFAULT '#1A1A1A',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.logged_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view categories"
  ON public.logged_categories FOR SELECT
  TO authenticated
  USING (true);



-- ── Logged Items ──────────────────────────────────────────────

-- array_to_string is marked STABLE by Postgres (conservatively, for all array types),
-- but for TEXT[] the output is purely deterministic. This wrapper allows its use in
-- index expressions, which require IMMUTABLE functions.
CREATE OR REPLACE FUNCTION public.text_array_to_string(arr TEXT[], sep TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
  SELECT array_to_string(arr, sep);
$$;

CREATE TYPE content_type_enum AS ENUM ('article', 'video', 'podcast');

CREATE TABLE IF NOT EXISTS public.logged_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  url TEXT NOT NULL,
  url_hash TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  category_id UUID REFERENCES public.logged_categories(id) ON DELETE SET NULL,
  preview_image_url TEXT,
  content_type content_type_enum NOT NULL DEFAULT 'article',
  raw_metadata JSONB DEFAULT '{}',
  tags TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_logged_items_category ON public.logged_items (category_id);
CREATE INDEX IF NOT EXISTS idx_logged_items_created ON public.logged_items (created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_logged_items_url_hash ON public.logged_items (url_hash);
CREATE INDEX idx_logged_items_search ON public.logged_items
  USING gin(to_tsvector('english'::regconfig, coalesce(title, '') || ' ' || coalesce(public.text_array_to_string(tags, ' '), '')));

ALTER TABLE public.logged_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view logged items"
  ON public.logged_items FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert logged items"
  ON public.logged_items FOR INSERT
  WITH CHECK (true);


-- ── Conversations (DMs + Groups) ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.conversations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  is_group    boolean DEFAULT FALSE,
  group_name  TEXT UNIQUE DEFAULT null,  -- NULL for DMs, set for groups
  group_max_members INTEGER NOT NULL DEFAULT 50,
  group_description TEXT NULL,
  invite_code text UNIQUE NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_conversations_updated ON public.conversations (updated_at DESC);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- NOTE: conversations SELECT/UPDATE policies reference conversation_members and are
-- defined below, after conversation_members is created.


-- ── Conversation members ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.conversation_members (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  convo_id    UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role        TEXT DEFAULT null,
  joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (convo_id, user_id)
);

CREATE INDEX idx_conversation_members_updated ON public.conversation_members (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_members_convo_id ON public.conversation_members (convo_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user_id ON public.conversation_members (user_id);

ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;

-- Simple self-only check to avoid circular dependency with conversations RLS
CREATE POLICY conversation_members_select ON public.conversation_members FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY conversation_members_insert ON public.conversation_members FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY conversation_members_update ON public.conversation_members FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- ── Conversations RLS (deferred until conversation_members exists) ────

-- CREATE POLICY conversations_select ON public.conversations FOR SELECT TO authenticated
--   USING (
--     EXISTS (
--       SELECT 1 FROM public.conversation_members
--       WHERE convo_id = conversations.id AND user_id = auth.uid()
--     )
--   );

-- CREATE POLICY conversations_insert ON public.conversations FOR INSERT TO authenticated WITH CHECK (true);

-- CREATE POLICY conversations_update ON public.conversations FOR UPDATE TO authenticated
--   USING (
--     EXISTS (
--       SELECT 1 FROM public.conversation_members
--       WHERE convo_id = conversations.id AND user_id = auth.uid()
--     )
--   );

CREATE POLICY "Users can VIEW own convo"
  ON public.conversations FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can INSERT own convo"
  ON public.conversations FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Users can UPDATE own convo"
  ON public.conversations FOR UPDATE
  TO authenticated
  USING (true);



-- ──  messages ─────────────────────────────────────────────

CREATE TYPE message_type_enum AS ENUM ('text', 'logged_item');

CREATE TABLE IF NOT EXISTS public.messages (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  convo_id       UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  message_type   message_type_enum DEFAULT 'text',
  message_text   TEXT NOT NULL,
  logged_item_id UUID DEFAULT NULL REFERENCES public.logged_items(id) ON DELETE SET NULL,
  message_parent_id UUID DEFAULT NULL REFERENCES public.messages(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_convo_id ON public.messages (convo_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages (sender_id);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY messages_select ON public.messages FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE convo_id = messages.convo_id AND user_id = auth.uid()
    )
  );

CREATE POLICY messages_insert ON public.messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE convo_id = messages.convo_id AND user_id = auth.uid()
    )
  );

CREATE POLICY messages_update ON public.messages FOR UPDATE TO authenticated
  USING (sender_id = auth.uid());

CREATE POLICY messages_delete ON public.messages FOR DELETE TO authenticated
  USING (sender_id = auth.uid());



-- ── Message Reactions ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.message_reactions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id  UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji       TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON public.message_reactions (message_id);

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY reactions_select ON public.message_reactions FOR SELECT TO authenticated USING (true);
CREATE POLICY reactions_insert ON public.message_reactions FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY reactions_delete ON public.message_reactions FOR DELETE TO authenticated USING (user_id = auth.uid());



-- ── Message Read Receipts ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.message_read_receipts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id  UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  delivered_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_read_receipts_message_id ON public.message_read_receipts (message_id);
CREATE INDEX IF NOT EXISTS idx_message_read_receipts_user_id ON public.message_read_receipts (user_id);

ALTER TABLE public.message_read_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY receipts_select ON public.message_read_receipts FOR SELECT TO authenticated USING (true);
CREATE POLICY receipts_insert ON public.message_read_receipts FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());



-- ──  group posts ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_posts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  convo_id       UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  logged_item_id UUID DEFAULT null REFERENCES public.logged_items(id) ON DELETE SET NULL,
  shared_by      UUID NOT NULL REFERENCES public.profiles(id),
  note           TEXT,
  shared_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_group_posts_convo_id ON public.group_posts (convo_id, shared_at DESC);
CREATE INDEX IF NOT EXISTS idx_group_posts_shared_by ON public.group_posts (shared_by);

ALTER TABLE public.group_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY group_posts_select ON public.group_posts FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE convo_id = group_posts.convo_id AND user_id = auth.uid()
    )
  );

CREATE POLICY group_posts_insert ON public.group_posts FOR INSERT TO authenticated
  WITH CHECK (
    shared_by = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE convo_id = group_posts.convo_id AND user_id = auth.uid()
    )
  );

CREATE POLICY group_posts_delete ON public.group_posts FOR DELETE TO authenticated
  USING (shared_by = auth.uid());



-- ──  group post likes ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_posts_likes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_post_id UUID NOT NULL REFERENCES public.group_posts(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (group_post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_posts_likes ON public.group_posts_likes (group_post_id);

ALTER TABLE public.group_posts_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY group_posts_likes_select ON public.group_posts_likes FOR SELECT TO authenticated USING (true);
CREATE POLICY group_posts_likes_insert ON public.group_posts_likes FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY group_posts_likes_delete ON public.group_posts_likes FOR DELETE TO authenticated USING (user_id = auth.uid());


-- ──  group post must_reads ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_posts_must_reads (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_post_id UUID NOT NULL REFERENCES public.group_posts(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (group_post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_posts_must_reads ON public.group_posts_must_reads (group_post_id);

ALTER TABLE public.group_posts_must_reads ENABLE ROW LEVEL SECURITY;

CREATE POLICY group_posts_must_reads_select ON public.group_posts_must_reads FOR SELECT TO authenticated USING (true);
CREATE POLICY group_posts_must_reads_insert ON public.group_posts_must_reads FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY group_posts_must_reads_delete ON public.group_posts_must_reads FOR DELETE TO authenticated USING (user_id = auth.uid());



-- ──  group post comments (shown in chat style) ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_posts_comments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_post_id     UUID NOT NULL REFERENCES public.group_posts(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  comment_text      TEXT NOT NULL,
  parent_comment_id UUID DEFAULT null REFERENCES public.group_posts_comments(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_group_posts_comments_post_id ON public.group_posts_comments (group_post_id);
CREATE INDEX IF NOT EXISTS idx_group_posts_comments_parent ON public.group_posts_comments (parent_comment_id);

ALTER TABLE public.group_posts_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY group_posts_comments_select ON public.group_posts_comments FOR SELECT TO authenticated USING (true);
CREATE POLICY group_posts_comments_insert ON public.group_posts_comments FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY group_posts_comments_update ON public.group_posts_comments FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY group_posts_comments_delete ON public.group_posts_comments FOR DELETE TO authenticated USING (user_id = auth.uid());





-- ── group posts comments read receipts─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_post_comments_read_receipts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id  UUID NOT NULL REFERENCES public.group_posts_comments(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  delivered_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (comment_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_post_comments_read_receipts_message_id ON public.group_post_comments_read_receipts (comment_id);
CREATE INDEX IF NOT EXISTS idx_group_post_comments_read_receipts_user_id ON public.group_post_comments_read_receipts (user_id);

ALTER TABLE public.group_post_comments_read_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY receipts_select ON public.group_post_comments_read_receipts FOR SELECT TO authenticated USING (true);
CREATE POLICY receipts_insert ON public.group_post_comments_read_receipts FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());


-- ── group posts reads ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_post_reads (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_post_id  UUID NOT NULL REFERENCES public.group_posts(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  read_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_group_post_reads_message_id ON public.group_post_reads (group_post_id);
CREATE INDEX IF NOT EXISTS idx_group_post_reads_user_id ON public.group_post_reads (user_id);

ALTER TABLE public.group_post_reads ENABLE ROW LEVEL SECURITY;

CREATE POLICY receipts_select ON public.group_post_reads FOR SELECT TO authenticated USING (true);
CREATE POLICY receipts_insert ON public.group_post_reads FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());




-- ── Group comments reactions ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_posts_comments_reactions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id  UUID NOT NULL REFERENCES public.group_posts_comments(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji       TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (comment_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_group_posts_comments_reactions_comment_id ON public.group_posts_comments_reactions (comment_id);

ALTER TABLE public.group_posts_comments_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY group_comment_reactions_select ON public.group_posts_comments_reactions FOR SELECT TO authenticated USING (true);
CREATE POLICY group_comment_reactions_insert ON public.group_posts_comments_reactions FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY group_comment_reactions_delete ON public.group_posts_comments_reactions FOR DELETE TO authenticated USING (user_id = auth.uid());



-- ── User logged Items ──────────────────────────────────────────────

CREATE TYPE save_source_enum AS ENUM ('external', 'shares', 'web_extension', 'discovered');

CREATE TABLE IF NOT EXISTS public.user_logged_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  logged_item_id UUID NOT NULL REFERENCES public.logged_items(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  save_source save_source_enum NOT NULL DEFAULT 'external',
  author uuid DEFAULT null REFERENCES public.profiles(id),
  shared_by uuid DEFAULT null REFERENCES public.profiles(id),
  saved_from_group uuid DEFAULT null REFERENCES public.conversations(id) ON DELETE SET NULL,
  remarks TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_logged_items_user_id ON public.user_logged_items (user_id);
CREATE INDEX IF NOT EXISTS idx_user_logged_items_created ON public.user_logged_items (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_logged_items_logged_item ON public.user_logged_items (logged_item_id);
CREATE INDEX IF NOT EXISTS idx_user_logged_items_saved_from_group ON public.user_logged_items (saved_from_group);


ALTER TABLE public.user_logged_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own items"
  ON public.user_logged_items FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own items"
  ON public.user_logged_items FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own items"
  ON public.user_logged_items FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own items"
  ON public.user_logged_items FOR DELETE
  USING (auth.uid() = user_id);





-- ── Reading Sessions ──────────────────────────────────────────

-- Tracks individual reading sessions per item.
-- session_end_time and duration are nullable while the session is active.
-- duration is INTEGER (seconds), client-provided.
-- completed = user reached the end of the article.
-- user_id is stored directly for efficient analytics queries and RLS.

CREATE TABLE IF NOT EXISTS public.reading_sessions (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  logged_item_id uuid NOT NULL REFERENCES public.logged_items(id) ON DELETE CASCADE,
  session_start_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  session_end_time TIMESTAMP WITH TIME ZONE,  -- null while session is active
  duration INTEGER,                            -- seconds, null while active
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  progress REAL NOT NULL DEFAULT '0'::real,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reading_sessions_user ON public.reading_sessions USING btree (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_reading_sessions_logged_item ON public.reading_sessions USING btree (logged_item_id, created_at);

ALTER TABLE public.reading_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can VIEW own reading sessions"
  ON public.reading_sessions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can INSERT own reading sessions"
  ON public.reading_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can UPDATE own reading sessions"
  ON public.reading_sessions FOR UPDATE
  USING (auth.uid() = user_id);


-- ── Events ────────────────────────────────────────────────────

-- Canonical lookup table of event types.
-- Metadata shape per event type:
--   view_log            { duration_seconds, scroll_depth_pct, device, country }
--   save_log            { save_source, content_type, device, country }
--   comment_log         { thread_id, comment_id, device, country }
--   share_log           { recipient_handle, share_method, device, country }
--                         share_method: 'dm' | 'thread' | 'person'
--   profile_view        { referrer, device, country }
--   external_link_click { device, country }

CREATE TABLE IF NOT EXISTS public.events (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  type        TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL
);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can READ event types"
  ON public.events FOR SELECT
  USING (TRUE);


-- ── User Events ───────────────────────────────────────────────

-- Full relational event log for all in-app interactions.
-- actor_user_id  — who performed the action (always set)
-- target_user_id — whose content was acted on; null for self-actions
-- log_id         — the content item involved; null for profile_view
-- url            — raw URL for external_link_click events

CREATE TABLE IF NOT EXISTS public.user_events (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_user_id UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  logged_item_id UUID        REFERENCES public.logged_items(id) ON DELETE SET NULL,
  event_type     TEXT        NOT NULL REFERENCES public.events(type),
  url            TEXT,
  metadata       JSONB       NOT NULL DEFAULT '{}',
  occurred_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_events_actor  ON public.user_events (actor_user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_events_target ON public.user_events (target_user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_events_log    ON public.user_events (logged_item_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_events_type   ON public.user_events (event_type, occurred_at DESC);

ALTER TABLE public.user_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can INSERT own events"
  ON public.user_events FOR INSERT
  WITH CHECK (auth.uid() = actor_user_id);

CREATE POLICY "Users can VIEW own events"
  ON public.user_events FOR SELECT
  USING (auth.uid() = actor_user_id);

CREATE POLICY "Users can VIEW events targeting them"
  ON public.user_events FOR SELECT
  USING (auth.uid() = target_user_id);


-- ── Stat Snapshots ────────────────────────────────────────────

-- Cached stats for public profile sharing.
-- slug is unique and human-readable.

CREATE TABLE IF NOT EXISTS public.stat_snapshots (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  slug         TEXT        NOT NULL UNIQUE,
  period_label TEXT        NOT NULL,  -- e.g. "Jan 2025", "Last 30 days"
  stats_json   JSONB       NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stat_snapshots_user ON public.stat_snapshots (user_id);
CREATE INDEX IF NOT EXISTS idx_stat_snapshots_slug ON public.stat_snapshots (slug);

ALTER TABLE public.stat_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own snapshots"
  ON public.stat_snapshots FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Anyone can VIEW snapshots BY slug"
  ON public.stat_snapshots FOR SELECT
  USING (TRUE);


-- ── User Stats Weekly ─────────────────────────────────────────

-- Pre-aggregated stats per ISO week.
-- week_start_date = the Monday of that week.
-- total_reading_time = sum of parsed read_time values in minutes.
-- unique_categories = count of distinct category_id values logged across the week.

CREATE TABLE IF NOT EXISTS public.user_stats_weekly (
  id                  UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID    NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  week_start_date     DATE    NOT NULL,
  UNIQUE (user_id, week_start_date),
  total_logs          INTEGER NOT NULL DEFAULT 0,
  total_reading_time  INTEGER NOT NULL DEFAULT 0,  -- minutes
  article_count       INTEGER NOT NULL DEFAULT 0,
  video_count         INTEGER NOT NULL DEFAULT 0,
  podcast_count       INTEGER NOT NULL DEFAULT 0,
  unique_categories   INTEGER NOT NULL DEFAULT 0,
  computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_stats_weekly_user_week ON public.user_stats_weekly (user_id, week_start_date DESC);

ALTER TABLE public.user_stats_weekly ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can VIEW own weekly stats"
  ON public.user_stats_weekly FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can upsert own weekly stats"
  ON public.user_stats_weekly FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can UPDATE own weekly stats"
  ON public.user_stats_weekly FOR UPDATE
  USING (auth.uid() = user_id);


-- ── User Stats Monthly ────────────────────────────────────────

-- Pre-aggregated stats per calendar month.
-- month_start_date = first day of the month.
-- total_reading_time = sum of parsed read_time values in minutes.
-- unique_categories = count of distinct category_id values logged across the month.

CREATE TABLE IF NOT EXISTS public.user_stats_monthly (
  id                  UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID    NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  month_start_date    DATE    NOT NULL,
  UNIQUE (user_id, month_start_date),
  total_logs          INTEGER NOT NULL DEFAULT 0,
  total_reading_time  INTEGER NOT NULL DEFAULT 0,  -- minutes
  article_count       INTEGER NOT NULL DEFAULT 0,
  video_count         INTEGER NOT NULL DEFAULT 0,
  podcast_count       INTEGER NOT NULL DEFAULT 0,
  unique_categories   INTEGER NOT NULL DEFAULT 0,
  computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_stats_monthly_user_month ON public.user_stats_monthly (user_id, month_start_date DESC);

ALTER TABLE public.user_stats_monthly ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can VIEW own monthly stats"
  ON public.user_stats_monthly FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can upsert own monthly stats"
  ON public.user_stats_monthly FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can UPDATE own monthly stats"
  ON public.user_stats_monthly FOR UPDATE
  USING (auth.uid() = user_id);