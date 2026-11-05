-- Rollen: Helfer -> Nutzer, Verwalter -> Gerätewart, neu: Admin
alter type public.user_role rename value 'helfer' to 'nutzer';
alter type public.user_role rename value 'verwalter' to 'geraetewart';
alter type public.user_role add value if not exists 'admin';
