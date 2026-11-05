-- Neue Rolle Einheitsführung (in eigener Migration, weil neue Enum-Werte erst nach dem Commit nutzbar sind)
alter type public.user_role add value if not exists 'einheitsfuehrung';
