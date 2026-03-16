-- ═══════════════════════════════════════════
-- 02_functions.sql
-- All functions, triggers, and stored procedures
-- ═══════════════════════════════════════════


-- ── Auto-create profile on signup ─────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_handle TEXT;
  v_base   TEXT;
BEGIN
  -- Derive base handle from email prefix; strip non-alphanumeric chars
  -- e.g. "john.doe+tag@gmail.com" → "johndoetag"
  v_base := regexp_replace(split_part(NEW.email, '@', 1), '[^a-zA-Z0-9_]', '', 'g');
  IF v_base = '' THEN v_base := 'user'; END IF;

  -- Find a unique handle by retrying with a new random suffix on collision
  LOOP
    v_handle := v_base || floor(random() * 9000 + 1000)::TEXT;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE handle = v_handle);
  END LOOP;

  INSERT INTO public.profiles (
    id,
    first_name,
    last_name,
    handle,
    avtar_url
  ) VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'given_name',
    NEW.raw_user_meta_data->>'family_name',
    v_handle,
    COALESCE(
      NEW.raw_user_meta_data->>'avatar_url',
      NEW.raw_user_meta_data->>'picture'
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ── Generic updated_at bumper ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_conversations_updated_at
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_conversation_members_updated_at
  BEFORE UPDATE ON public.conversation_members
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_messages_updated_at
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ── Auto-update conversations.updated_at on new message ───────

CREATE OR REPLACE FUNCTION public.update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.conversations SET updated_at = NEW.created_at WHERE id = NEW.convo_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_conversation_timestamp
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.update_conversation_timestamp();


-- ── Auto-update conversations.updated_at on new group post ────

CREATE OR REPLACE FUNCTION public.update_conversation_on_group_post()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.conversations SET updated_at = NEW.shared_at WHERE id = NEW.convo_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_conversation_on_group_post
  AFTER INSERT ON public.group_posts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_conversation_on_group_post();


-- ── Update weekly/monthly stats when a user logs an item ──────

CREATE OR REPLACE FUNCTION public.update_user_stats_on_log()
RETURNS TRIGGER AS $$
DECLARE
  v_content_type      content_type_enum;
  v_week_start        DATE;
  v_month_start       DATE;
  v_unique_cats_week  INTEGER;
  v_unique_cats_month INTEGER;
BEGIN
  SELECT content_type INTO v_content_type
  FROM public.logged_items WHERE id = NEW.logged_item_id;

  v_week_start  := date_trunc('week',  NEW.created_at)::DATE;
  v_month_start := date_trunc('month', NEW.created_at)::DATE;

  -- Recount unique categories for this user in the affected week/month
  SELECT COUNT(DISTINCT li.category_id) INTO v_unique_cats_week
  FROM public.user_logged_items uli
  JOIN public.logged_items li ON li.id = uli.logged_item_id
  WHERE uli.user_id = NEW.user_id
    AND date_trunc('week', uli.created_at)::DATE = v_week_start
    AND li.category_id IS NOT NULL;

  SELECT COUNT(DISTINCT li.category_id) INTO v_unique_cats_month
  FROM public.user_logged_items uli
  JOIN public.logged_items li ON li.id = uli.logged_item_id
  WHERE uli.user_id = NEW.user_id
    AND date_trunc('month', uli.created_at)::DATE = v_month_start
    AND li.category_id IS NOT NULL;

  INSERT INTO public.user_stats_weekly (
    user_id, week_start_date,
    total_logs, article_count, video_count, podcast_count, unique_categories
  ) VALUES (
    NEW.user_id, v_week_start,
    1,
    CASE WHEN v_content_type = 'article' THEN 1 ELSE 0 END,
    CASE WHEN v_content_type = 'video'   THEN 1 ELSE 0 END,
    CASE WHEN v_content_type = 'podcast' THEN 1 ELSE 0 END,
    v_unique_cats_week
  )
  ON CONFLICT (user_id, week_start_date) DO UPDATE SET
    total_logs        = user_stats_weekly.total_logs + 1,
    article_count     = user_stats_weekly.article_count  + CASE WHEN v_content_type = 'article' THEN 1 ELSE 0 END,
    video_count       = user_stats_weekly.video_count    + CASE WHEN v_content_type = 'video'   THEN 1 ELSE 0 END,
    podcast_count     = user_stats_weekly.podcast_count  + CASE WHEN v_content_type = 'podcast' THEN 1 ELSE 0 END,
    unique_categories = v_unique_cats_week,
    computed_at       = NOW();

  INSERT INTO public.user_stats_monthly (
    user_id, month_start_date,
    total_logs, article_count, video_count, podcast_count, unique_categories
  ) VALUES (
    NEW.user_id, v_month_start,
    1,
    CASE WHEN v_content_type = 'article' THEN 1 ELSE 0 END,
    CASE WHEN v_content_type = 'video'   THEN 1 ELSE 0 END,
    CASE WHEN v_content_type = 'podcast' THEN 1 ELSE 0 END,
    v_unique_cats_month
  )
  ON CONFLICT (user_id, month_start_date) DO UPDATE SET
    total_logs        = user_stats_monthly.total_logs + 1,
    article_count     = user_stats_monthly.article_count  + CASE WHEN v_content_type = 'article' THEN 1 ELSE 0 END,
    video_count       = user_stats_monthly.video_count    + CASE WHEN v_content_type = 'video'   THEN 1 ELSE 0 END,
    podcast_count     = user_stats_monthly.podcast_count  + CASE WHEN v_content_type = 'podcast' THEN 1 ELSE 0 END,
    unique_categories = v_unique_cats_month,
    computed_at       = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_stats_on_log
  AFTER INSERT ON public.user_logged_items
  FOR EACH ROW EXECUTE FUNCTION public.update_user_stats_on_log();


-- ── Decrement weekly/monthly stats when a logged item is removed ─

CREATE OR REPLACE FUNCTION public.update_user_stats_on_log_delete()
RETURNS TRIGGER AS $$
DECLARE
  v_content_type      content_type_enum;
  v_week_start        DATE;
  v_month_start       DATE;
  v_unique_cats_week  INTEGER;
  v_unique_cats_month INTEGER;
BEGIN
  SELECT content_type INTO v_content_type
  FROM public.logged_items WHERE id = OLD.logged_item_id;

  v_week_start  := date_trunc('week',  OLD.created_at)::DATE;
  v_month_start := date_trunc('month', OLD.created_at)::DATE;

  -- Recount after the delete (OLD row already removed from table)
  SELECT COUNT(DISTINCT li.category_id) INTO v_unique_cats_week
  FROM public.user_logged_items uli
  JOIN public.logged_items li ON li.id = uli.logged_item_id
  WHERE uli.user_id = OLD.user_id
    AND date_trunc('week', uli.created_at)::DATE = v_week_start
    AND li.category_id IS NOT NULL;

  SELECT COUNT(DISTINCT li.category_id) INTO v_unique_cats_month
  FROM public.user_logged_items uli
  JOIN public.logged_items li ON li.id = uli.logged_item_id
  WHERE uli.user_id = OLD.user_id
    AND date_trunc('month', uli.created_at)::DATE = v_month_start
    AND li.category_id IS NOT NULL;

  UPDATE public.user_stats_weekly SET
    total_logs        = GREATEST(total_logs - 1, 0),
    article_count     = GREATEST(article_count  - CASE WHEN v_content_type = 'article' THEN 1 ELSE 0 END, 0),
    video_count       = GREATEST(video_count    - CASE WHEN v_content_type = 'video'   THEN 1 ELSE 0 END, 0),
    podcast_count     = GREATEST(podcast_count  - CASE WHEN v_content_type = 'podcast' THEN 1 ELSE 0 END, 0),
    unique_categories = v_unique_cats_week,
    computed_at       = NOW()
  WHERE user_id = OLD.user_id AND week_start_date = v_week_start;

  UPDATE public.user_stats_monthly SET
    total_logs        = GREATEST(total_logs - 1, 0),
    article_count     = GREATEST(article_count  - CASE WHEN v_content_type = 'article' THEN 1 ELSE 0 END, 0),
    video_count       = GREATEST(video_count    - CASE WHEN v_content_type = 'video'   THEN 1 ELSE 0 END, 0),
    podcast_count     = GREATEST(podcast_count  - CASE WHEN v_content_type = 'podcast' THEN 1 ELSE 0 END, 0),
    unique_categories = v_unique_cats_month,
    computed_at       = NOW()
  WHERE user_id = OLD.user_id AND month_start_date = v_month_start;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_stats_on_log_delete
  AFTER DELETE ON public.user_logged_items
  FOR EACH ROW EXECUTE FUNCTION public.update_user_stats_on_log_delete();


-- ── Accumulate reading time when a session completes ──────────

CREATE OR REPLACE FUNCTION public.update_reading_time_on_session()
RETURNS TRIGGER AS $$
DECLARE
  v_week_start    DATE;
  v_month_start   DATE;
  v_minutes_added INTEGER;
BEGIN
  -- Only fire when duration transitions NULL → value (session just completed)
  IF NEW.duration IS NULL OR OLD.duration IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_week_start    := date_trunc('week',  NEW.created_at)::DATE;
  v_month_start   := date_trunc('month', NEW.created_at)::DATE;
  v_minutes_added := GREATEST(ROUND(NEW.duration / 60.0)::INTEGER, 0);

  UPDATE public.user_stats_weekly SET
    total_reading_time = total_reading_time + v_minutes_added,
    computed_at        = NOW()
  WHERE user_id = NEW.user_id AND week_start_date = v_week_start;

  UPDATE public.user_stats_monthly SET
    total_reading_time = total_reading_time + v_minutes_added,
    computed_at        = NOW()
  WHERE user_id = NEW.user_id AND month_start_date = v_month_start;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_reading_time
  AFTER UPDATE ON public.reading_sessions
  FOR EACH ROW EXECUTE FUNCTION public.update_reading_time_on_session();


-- ── Group Invite Email Notification ───────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.notify_group_invite_email()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM extensions.net.http_post(
    url     := current_setting('app.edge_function_base_url', true) || '/send-group-invite-email',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
               ),
    body    := jsonb_build_object(
                 'invite_id',   NEW.id,
                 'group_id',    NEW.group_id,
                 'invited_by',  NEW.invited_by,
                 'email',       NEW.email,
                 'invite_code', NEW.invite_code,
                 'expires_at',  NEW.expires_at
               )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_group_invite_email
  AFTER INSERT ON public.group_invites
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_group_invite_email();


-- ── Accept Group Invite ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.accept_group_invite(p_invite_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invite    public.group_invites%ROWTYPE;
  v_member_id UUID;
BEGIN
  SELECT * INTO v_invite
  FROM public.group_invites
  WHERE invite_code = p_invite_code
  FOR UPDATE;  -- prevents concurrent double-accepts

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'invite_not_found');
  END IF;

  IF v_invite.status <> 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'invite_already_used', 'status', v_invite.status);
  END IF;

  IF v_invite.expires_at < now() THEN
    UPDATE public.group_invites SET status = 'expired' WHERE id = v_invite.id;
    RETURN jsonb_build_object('success', false, 'error', 'invite_expired');
  END IF;

  -- Verify caller's email matches the invite recipient
  IF lower(auth.jwt() ->> 'email') <> lower(v_invite.email) THEN
    RETURN jsonb_build_object('success', false, 'error', 'email_mismatch');
  END IF;

  -- Enforce group member cap
  IF (SELECT COUNT(*) FROM public.conversation_members WHERE convo_id = v_invite.group_id)
     >= (SELECT group_max_members FROM public.conversations WHERE id = v_invite.group_id)
  THEN
    RETURN jsonb_build_object('success', false, 'error', 'group_full');
  END IF;

  -- UPSERT: user may already be a member (joined via shareable link)
  INSERT INTO public.conversation_members (convo_id, user_id)
  VALUES (v_invite.group_id, auth.uid())
  ON CONFLICT (convo_id, user_id) DO NOTHING
  RETURNING id INTO v_member_id;

  UPDATE public.group_invites
  SET status = 'accepted', accepted_at = now()
  WHERE id = v_invite.id;

  RETURN jsonb_build_object(
    'success',   true,
    'group_id',  v_invite.group_id,
    'member_id', COALESCE(v_member_id,
      (SELECT id FROM public.conversation_members WHERE convo_id = v_invite.group_id AND user_id = auth.uid()))
  );
END;
$$;


-- ── Expire Stale Invites ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.expire_stale_invites()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_count INTEGER;
BEGIN
  UPDATE public.group_invites
  SET status = 'expired'
  WHERE status = 'pending' AND expires_at < now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
-- Optional: schedule with pg_cron (enable extension first)
-- SELECT cron.schedule('expire-group-invites', '0 * * * *', 'SELECT public.expire_stale_invites()');
