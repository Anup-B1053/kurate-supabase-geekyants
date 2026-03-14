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
  -- Derive a base handle from email (part before @)
  v_base := split_part(NEW.email, '@', 1);
  -- Append 4 random digits to reduce collision chance
  v_handle := v_base || floor(random() * 9000 + 1000)::TEXT;

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


-- ── Auto-update conversations.updated_at on new message ───────

CREATE OR REPLACE FUNCTION public.update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.conversations SET updated_at = NEW.created_at WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_conversation_timestamp
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.update_conversation_timestamp();
