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


-- ═══════════════════════════════════════════════════════════
-- Notification triggers
-- ═══════════════════════════════════════════════════════════

-- Enable pg_net for async HTTP calls
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ── Helper: fire FCM edge function asynchronously ─────────

CREATE OR REPLACE FUNCTION public.notify_via_fcm(p_notification_id UUID)
RETURNS VOID AS $$
BEGIN
  PERFORM pg_net.http_post(
    url     := current_setting('app.supabase_url', true) || '/functions/v1/send-fcm',
    body    := jsonb_build_object('notification_id', p_notification_id),
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ── Like: INSERT ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_like_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_recipient         UUID;
  v_notif_id          UUID;
  v_like_notifs       BOOLEAN;
  v_push_enabled      BOOLEAN;
BEGIN
  -- Get post author
  SELECT shared_by INTO v_recipient FROM public.group_posts WHERE id = NEW.group_post_id;

  -- Skip self-like
  IF NEW.user_id = v_recipient THEN RETURN NEW; END IF;

  -- Check preferences (default true if no row exists)
  SELECT like_notifications, push_enabled
    INTO v_like_notifs, v_push_enabled
    FROM public.notification_preferences
   WHERE user_id = v_recipient;

  IF v_like_notifs = FALSE THEN RETURN NEW; END IF;

  -- Find existing aggregated notification for this post
  SELECT id INTO v_notif_id
    FROM public.notifications
   WHERE recipient_id = v_recipient
     AND event_type = 'like'
     AND event_id = NEW.group_post_id;

  IF v_notif_id IS NULL THEN
    -- First like: create notification and fire FCM
    INSERT INTO public.notifications (recipient_id, actor_id, event_type, event_id, message)
    VALUES (v_recipient, NEW.user_id, 'like', NEW.group_post_id, 'liked your post')
    RETURNING id INTO v_notif_id;

    INSERT INTO public.notification_actors (notification_id, actor_id)
    VALUES (v_notif_id, NEW.user_id)
    ON CONFLICT DO NOTHING;

    PERFORM public.notify_via_fcm(v_notif_id);
  ELSE
    -- Subsequent like: update actor only, no re-push
    INSERT INTO public.notification_actors (notification_id, actor_id)
    VALUES (v_notif_id, NEW.user_id)
    ON CONFLICT DO NOTHING;

    UPDATE public.notifications
       SET actor_id = NEW.user_id, updated_at = NOW()
     WHERE id = v_notif_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_like_notification
  AFTER INSERT ON public.group_posts_likes
  FOR EACH ROW EXECUTE FUNCTION public.handle_like_insert();


-- ── Like: DELETE ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_like_delete()
RETURNS TRIGGER AS $$
DECLARE
  v_recipient UUID;
  v_notif_id  UUID;
  v_remaining INTEGER;
BEGIN
  SELECT shared_by INTO v_recipient FROM public.group_posts WHERE id = OLD.group_post_id;

  SELECT id INTO v_notif_id
    FROM public.notifications
   WHERE recipient_id = v_recipient
     AND event_type = 'like'
     AND event_id = OLD.group_post_id;

  IF v_notif_id IS NULL THEN RETURN OLD; END IF;

  DELETE FROM public.notification_actors
   WHERE notification_id = v_notif_id AND actor_id = OLD.user_id;

  SELECT COUNT(*) INTO v_remaining
    FROM public.notification_actors
   WHERE notification_id = v_notif_id;

  IF v_remaining = 0 THEN
    DELETE FROM public.notifications WHERE id = v_notif_id;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_like_delete_notification
  AFTER DELETE ON public.group_posts_likes
  FOR EACH ROW EXECUTE FUNCTION public.handle_like_delete();


-- ── Must-Read: INSERT ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_must_read_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_recipient          UUID;
  v_notif_id           UUID;
  v_must_read_notifs   BOOLEAN;
  v_push_enabled       BOOLEAN;
BEGIN
  SELECT shared_by INTO v_recipient FROM public.group_posts WHERE id = NEW.group_post_id;

  IF NEW.user_id = v_recipient THEN RETURN NEW; END IF;

  SELECT must_read_notifications, push_enabled
    INTO v_must_read_notifs, v_push_enabled
    FROM public.notification_preferences
   WHERE user_id = v_recipient;

  IF v_must_read_notifs = FALSE THEN RETURN NEW; END IF;

  SELECT id INTO v_notif_id
    FROM public.notifications
   WHERE recipient_id = v_recipient
     AND event_type = 'must_read'
     AND event_id = NEW.group_post_id;

  IF v_notif_id IS NULL THEN
    INSERT INTO public.notifications (recipient_id, actor_id, event_type, event_id, message)
    VALUES (v_recipient, NEW.user_id, 'must_read', NEW.group_post_id, 'marked your post as must-read')
    RETURNING id INTO v_notif_id;

    INSERT INTO public.notification_actors (notification_id, actor_id)
    VALUES (v_notif_id, NEW.user_id)
    ON CONFLICT DO NOTHING;

    PERFORM public.notify_via_fcm(v_notif_id);
  ELSE
    INSERT INTO public.notification_actors (notification_id, actor_id)
    VALUES (v_notif_id, NEW.user_id)
    ON CONFLICT DO NOTHING;

    UPDATE public.notifications
       SET actor_id = NEW.user_id, updated_at = NOW()
     WHERE id = v_notif_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_must_read_notification
  AFTER INSERT ON public.group_posts_must_reads
  FOR EACH ROW EXECUTE FUNCTION public.handle_must_read_insert();


-- ── Must-Read: DELETE ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_must_read_delete()
RETURNS TRIGGER AS $$
DECLARE
  v_recipient UUID;
  v_notif_id  UUID;
  v_remaining INTEGER;
BEGIN
  SELECT shared_by INTO v_recipient FROM public.group_posts WHERE id = OLD.group_post_id;

  SELECT id INTO v_notif_id
    FROM public.notifications
   WHERE recipient_id = v_recipient
     AND event_type = 'must_read'
     AND event_id = OLD.group_post_id;

  IF v_notif_id IS NULL THEN RETURN OLD; END IF;

  DELETE FROM public.notification_actors
   WHERE notification_id = v_notif_id AND actor_id = OLD.user_id;

  SELECT COUNT(*) INTO v_remaining
    FROM public.notification_actors
   WHERE notification_id = v_notif_id;

  IF v_remaining = 0 THEN
    DELETE FROM public.notifications WHERE id = v_notif_id;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_must_read_delete_notification
  AFTER DELETE ON public.group_posts_must_reads
  FOR EACH ROW EXECUTE FUNCTION public.handle_must_read_delete();


-- ── Comment: INSERT (no aggregation) ──────────────────────

CREATE OR REPLACE FUNCTION public.handle_comment_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_recipient        UUID;
  v_notif_id         UUID;
  v_comment_notifs   BOOLEAN;
  v_push_enabled     BOOLEAN;
BEGIN
  SELECT shared_by INTO v_recipient FROM public.group_posts WHERE id = NEW.group_post_id;

  IF NEW.user_id = v_recipient THEN RETURN NEW; END IF;

  SELECT comment_notifications, push_enabled
    INTO v_comment_notifs, v_push_enabled
    FROM public.notification_preferences
   WHERE user_id = v_recipient;

  IF v_comment_notifs = FALSE THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (recipient_id, actor_id, event_type, event_id, message)
  VALUES (v_recipient, NEW.user_id, 'comment', NEW.group_post_id, 'commented on your post')
  RETURNING id INTO v_notif_id;

  PERFORM public.notify_via_fcm(v_notif_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_comment_notification
  AFTER INSERT ON public.group_posts_comments
  FOR EACH ROW EXECUTE FUNCTION public.handle_comment_insert();


-- ── New Post: fan-out per group member ─────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_post_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_content_type    TEXT;
  v_handle          TEXT;
  v_group_name      TEXT;
  v_member          RECORD;
  v_notif_id        UUID;
  v_new_post_notifs BOOLEAN;
  v_push_enabled    BOOLEAN;
BEGIN
  SELECT content_type::TEXT INTO v_content_type
    FROM public.logged_items WHERE id = NEW.logged_item_id;

  SELECT handle INTO v_handle
    FROM public.profiles WHERE id = NEW.shared_by;

  SELECT group_name INTO v_group_name
    FROM public.conversations WHERE id = NEW.convo_id;

  FOR v_member IN
    SELECT user_id FROM public.conversation_members
     WHERE convo_id = NEW.convo_id AND user_id != NEW.shared_by
  LOOP
    SELECT new_post_notifications, push_enabled
      INTO v_new_post_notifs, v_push_enabled
      FROM public.notification_preferences
     WHERE user_id = v_member.user_id;

    IF v_new_post_notifs = FALSE THEN
      CONTINUE;
    END IF;

    INSERT INTO public.notifications (recipient_id, actor_id, event_type, event_id, message)
    VALUES (
      v_member.user_id,
      NEW.shared_by,
      'new_post',
      NEW.id,
      v_handle || ' shared a ' || COALESCE(v_content_type, 'post') || ' in ' || COALESCE(v_group_name, 'your group')
    )
    RETURNING id INTO v_notif_id;

    PERFORM public.notify_via_fcm(v_notif_id);
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_new_post_notification
  AFTER INSERT ON public.group_posts
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_post_insert();
