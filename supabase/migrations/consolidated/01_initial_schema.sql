-- ═══════════════════════════════════════════
-- 01_initial_schema.sql
-- All table definitions, indexes, and RLS policies
-- ═══════════════════════════════════════════


-- ── Profiles ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name TEXT,
  last_name TEXT,
  handle TEXT,
  about TEXT,
  interests TEXT[] DEFAULT '{}',
  is_onboarded BOOLEAN NOT NULL DEFAULT FALSE,
  avtar_url TEXT,
  xp INTEGER NOT NULL DEFAULT 0,
  theme_pref TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can VIEW own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can UPDATE own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);


-- ── Person Shares ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.person_shares (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  sharer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  recipient_handle text NOT NULL,
  recipient_name text NOT NULL,
  url text NOT NULL,
  title text NULL,
  source text NULL,
  preview_image text NULL,
  content_type text NOT NULL DEFAULT 'article'::text,
  read_time text NULL,
  received_from_handle text NULL,
  received_from_name text NULL,
  shared_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_person_shares_sharer ON public.person_shares USING btree (sharer_id, shared_at DESC);
CREATE INDEX IF NOT EXISTS idx_person_shares_recipient ON public.person_shares USING btree (recipient_handle, shared_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_person_shares_dedup ON public.person_shares USING btree (sharer_id, recipient_handle, url);

ALTER TABLE public.person_shares ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own shares"
  ON public.person_shares FOR SELECT
  USING (auth.uid() = sharer_id);

CREATE POLICY "Users can insert own shares"
  ON public.person_shares FOR INSERT
  WITH CHECK (auth.uid() = sharer_id);

CREATE POLICY "Users can delete own shares"
  ON public.person_shares FOR DELETE
  USING (auth.uid() = sharer_id);


-- ── Companions ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.companions (
  user_id uuid PRIMARY KEY NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  stage SMALLINT NOT NULL DEFAULT 1,
  avatar_url text NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);


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


-- ── Follows ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.follows (
  follower_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (follower_id, following_id),
  CONSTRAINT no_self_follow CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_follower  ON public.follows (follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON public.follows (following_id);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view follows"
  ON public.follows FOR SELECT
  USING (true);

CREATE POLICY "Users can follow others"
  ON public.follows FOR INSERT
  WITH CHECK (auth.uid() = follower_id);

CREATE POLICY "Users can unfollow"
  ON public.follows FOR DELETE
  USING (auth.uid() = follower_id);


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

CREATE TABLE IF NOT EXISTS public.logged_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  title TEXT,
  source TEXT,
  author TEXT,
  category_id UUID REFERENCES public.logged_categories(id) ON DELETE SET NULL,
  preview_image TEXT,
  content_type TEXT NOT NULL DEFAULT 'article', -- article, video, podcast
  save_source TEXT NOT NULL DEFAULT 'logged',   -- logged, shared, extension
  read_time TEXT,
  shared_from_name TEXT,
  shared_from_handle TEXT,
  shared_to_groups TEXT[] DEFAULT '{}',
  remarks TEXT,
  tags TEXT[] DEFAULT '{}',
  raw_metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_logged_items_category ON public.logged_items (user_id, category_id);
CREATE INDEX IF NOT EXISTS idx_logged_items_user_created ON public.logged_items (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_logged_items_user_url ON public.logged_items (user_id, url);
CREATE INDEX idx_logged_items_search ON public.logged_items
  USING gin(to_tsvector('english', coalesce(title, '') || ' ' || coalesce(remarks, '')));
CREATE INDEX IF NOT EXISTS idx_logged_items_shared_to_groups ON public.logged_items USING GIN (shared_to_groups);

ALTER TABLE public.logged_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own items"
  ON public.logged_items FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own items"
  ON public.logged_items FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own items"
  ON public.logged_items FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own items"
  ON public.logged_items FOR DELETE
  USING (auth.uid() = user_id);


-- ── logged_item_likes ────────────────────────────────────────────────────
create table public.logged_item_likes (
  id uuid primary key default (),
  created_at timestamp with time zone not null default now(),
  logged_item_id uuid not null references public.logged_items(id),
  user_id uuid not null references public.profiles(id),
  constraint logged_item_likes_logged_item_id_fkey foreign KEY (logged_item_id) references logged_items (id),
  constraint logged_item_likes_user_id_fkey foreign KEY (user_id) references profiles (id)
) TABLESPACE pg_default;

CREATE POLICY "Everyone can view likes" 
ON public.logged_item_likes FOR SELECT 
USING (true);

-- ── logged_item_must_reads ────────────────────────────────────────────────────
create table public.logged_item_must_reads (
  id uuid primary key default (),
  created_at timestamp with time zone not null default now(),
  logged_item_id uuid not null references public.logged_items(id),
  user_id uuid not null references public.profiles(id),
  constraint logged_item_must_reads_logged_item_id_fkey foreign KEY (logged_item_id) references logged_items (id),
  constraint logged_item_must_reads_user_id_fkey foreign KEY (user_id) references profiles (id)
) TABLESPACE pg_default;

CREATE POLICY "Everyone can view must reads" 
ON public.logged_item_must_reads FOR SELECT 
USING (true);


-- ── logged_item_saves ────────────────────────────────────────────────────
create table public.logged_item_saves (
  id uuid primary key default (),
  created_at timestamp with time zone not null default now(),
  logged_item_id uuid not null references public.logged_items(id),
  user_id uuid not null references public.profiles(id),
  constraint logged_item_saves_logged_item_id_fkey foreign KEY (logged_item_id) references logged_items (id),
  constraint logged_item_saves_user_id_fkey foreign KEY (user_id) references profiles (id)
) TABLESPACE pg_default;

CREATE POLICY "Everyone can view saves" 
ON public.logged_item_saves FOR SELECT 
USING (true);




-- ── Groups ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.groups (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text NULL,
  created_by uuid NOT NULL REFERENCES public.profiles(id),
  invite_code text UNIQUE NOT NULL,
  max_members INTEGER NOT NULL DEFAULT 20,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_invite ON public.groups USING btree (invite_code) TABLESPACE pg_default;


-- ── Group Members ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_members (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_admin BOOLEAN NOT NULL DEFAULT FALSE,
  role text NOT NULL DEFAULT 'member'::text,
  status text NOT NULL DEFAULT 'pending'::text,
  joined_at TIMESTAMP WITH TIME ZONE NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_group_members_unique ON public.group_members USING btree (group_id, user_id) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS idx_group_members_user ON public.group_members USING btree (user_id, status) TABLESPACE pg_default;


-- ── Group Shares ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.group_shares (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  logged_item_id uuid NOT NULL REFERENCES public.logged_items(id) ON DELETE CASCADE,
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  shared_by uuid NOT NULL REFERENCES public.profiles(id),
  note text NULL,
  shared_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_group_shares_unique ON public.group_shares USING btree (logged_item_id, group_id, shared_by) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS idx_group_shares_group ON public.group_shares USING btree (group_id, shared_at DESC) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS idx_group_shares_item ON public.group_shares USING btree (logged_item_id) TABLESPACE pg_default;


-- ── Comments ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.comments (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  group_share_id uuid NOT NULL REFERENCES public.group_shares(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id),
  content text NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_comments_share ON public.comments USING btree (group_share_id, created_at) TABLESPACE pg_default;


-- ── Reactions ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.reactions (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  group_share_id uuid NOT NULL REFERENCES public.group_shares(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id),
  comment_id uuid NOT NULL REFERENCES public.comments(id) ON DELETE CASCADE,
  type text NOT NULL DEFAULT 'upvote'::text,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_reactions_unique ON public.reactions USING btree (group_share_id, user_id, type) TABLESPACE pg_default;


-- ── Reading Sessions ──────────────────────────────────────────

-- Tracks individual reading sessions per item.
-- session_end_time and duration are nullable while the session is active.
-- duration is INTEGER (seconds), client-provided.
-- completed = user reached the end of the article.
-- user_id is stored directly for efficient analytics queries and RLS.

CREATE TABLE IF NOT EXISTS public.reading_sessions (
  id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON UPDATE CASCADE,
  logged_item_id uuid NOT NULL REFERENCES public.logged_items(id) ON UPDATE CASCADE,
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
  

-- ── Conversations ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.conversations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type        TEXT NOT NULL CHECK (type IN ('dm', 'group')),
  name        TEXT,  -- NULL for DMs, set for groups
  created_by  UUID REFERENCES public.profiles(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_conversations_updated ON public.conversations (updated_at DESC);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY conversations_select ON public.conversations FOR SELECT TO authenticated USING (true);
CREATE POLICY conversations_insert ON public.conversations FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY conversations_update ON public.conversations FOR UPDATE TO authenticated USING (true);


-- ── Conversation Members ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.conversation_members (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_handle     TEXT NOT NULL,
  user_name       TEXT NOT NULL,
  user_id         UUID,  -- NULL for mock contacts
  role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (conversation_id, user_handle)
);

CREATE INDEX idx_conversation_members_handle ON public.conversation_members (user_handle);

ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY members_select ON public.conversation_members FOR SELECT TO authenticated USING (true);
CREATE POLICY members_insert ON public.conversation_members FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY members_delete ON public.conversation_members FOR DELETE TO authenticated USING (true);


-- ── Messages ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_handle   TEXT NOT NULL,
  sender_name     TEXT NOT NULL,
  sender_id       UUID,  -- NULL for mock senders
  content         TEXT NOT NULL DEFAULT '',
  message_type    TEXT NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'link', 'image', 'forward')),
  link_preview    JSONB,  -- { url, title, source, image, description }
  image_url       TEXT,
  forwarded_from  JSONB,  -- { senderName, senderHandle, conversationName }
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_timeline ON public.messages (conversation_id, created_at DESC);
CREATE INDEX idx_messages_type     ON public.messages (conversation_id, message_type);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY messages_select ON public.messages FOR SELECT TO authenticated USING (true);
CREATE POLICY messages_insert ON public.messages FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY messages_update ON public.messages FOR UPDATE TO authenticated USING (true);


-- ── Message Reactions ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.message_reactions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id  UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_handle TEXT NOT NULL,
  emoji       TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_handle, emoji)
);

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY reactions_select ON public.message_reactions FOR SELECT TO authenticated USING (true);
CREATE POLICY reactions_insert ON public.message_reactions FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY reactions_delete ON public.message_reactions FOR DELETE TO authenticated USING (true);


-- ── Message Read Receipts ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.message_read_receipts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id  UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_handle TEXT NOT NULL,
  read_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_handle)
);

ALTER TABLE public.message_read_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY receipts_select ON public.message_read_receipts FOR SELECT TO authenticated USING (true);
CREATE POLICY receipts_insert ON public.message_read_receipts FOR INSERT TO authenticated WITH CHECK (true);


-- ── Realtime ──────────────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions;
