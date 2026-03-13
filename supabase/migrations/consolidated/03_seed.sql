-- ═══════════════════════════════════════════
-- 03_seed.sql
-- All seed / reference data
-- ═══════════════════════════════════════════


-- ── Interests ─────────────────────────────────────────────────

INSERT INTO public.interests (name) VALUES
  ('Technology'),
  ('Design'),
  ('Business'),
  ('Science'),
  ('Health & Fitness'),
  ('Travel'),
  ('Food & Cooking'),
  ('Music'),
  ('Art'),
  ('Sports'),
  ('Finance'),
  ('Education'),
  ('Gaming'),
  ('Fashion'),
  ('Photography'),
  ('Writing'),
  ('Film & TV'),
  ('Politics'),
  ('History'),
  ('Philosophy'),
  ('Psychology'),
  ('Environment'),
  ('Parenting'),
  ('Self-Improvement'),
  ('Architecture')
ON CONFLICT (name) DO NOTHING;


-- ── Logged Categories ─────────────────────────────────────────

INSERT INTO public.logged_categories (name, slug, color) VALUES
  ('Technology',    'technology',    '#1A5C4B'),
  ('Design',        'design',        '#C94F2C'),
  ('Business',      'business',      '#2C5F8A'),
  ('Finance',       'finance',       '#7A4F9E'),
  ('Science',       'science',       '#2E7D5E'),
  ('Health',        'health',        '#D4882A'),
  ('Politics',      'politics',      '#8B2E2E'),
  ('Culture',       'culture',       '#4A6741'),
  ('Education',     'education',     '#3D5A80'),
  ('Environment',   'environment',   '#3A7D44'),
  ('Entertainment', 'entertainment', '#B5451B'),
  ('Sports',        'sports',        '#1B4F72'),
  ('Food',          'food',          '#A0522D'),
  ('Travel',        'travel',        '#2E6B8A'),
  ('Other',         'other',         '#6B6B6B')
ON CONFLICT (slug) DO NOTHING;


-- ── Events ────────────────────────────────────────────────────

INSERT INTO public.events (type, description) VALUES
  ('view_log',            'User viewed a logged item in the vault'),
  ('save_log',            'User saved or logged a new item'),
  ('comment_log',         'User commented on a content thread'),
  ('share_log',           'User shared a logged item with someone'),
  ('profile_view',        'User viewed another user''s profile'),
  ('external_link_click', 'User opened an external link from a logged item')
ON CONFLICT (type) DO NOTHING;
