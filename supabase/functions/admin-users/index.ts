import { createClient } from "npm:@supabase/supabase-js@2";

const USER_DOMAIN = "abc-zug-heinsberg.de";
const ROLES = ["nutzer", "geraetewart", "einheitsfuehrung", "admin"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Nur POST erlaubt." }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Aufrufer prüfen: muss angemeldet sein und Admin oder Einheitsführung
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "Nicht angemeldet." }, 401);

  const admin = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: me } = await admin.from("profiles").select("role").eq("id", user.id).maybeSingle();
  const isAdmin = me?.role === "admin";
  const isEF = me?.role === "einheitsfuehrung";
  if (!isAdmin && !isEF) return json({ error: "Keine Berechtigung für die Benutzerverwaltung." }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Ungültige Anfrage." }, 400); }
  const action = body?.action;

  // Die Einheitsführung darf nur Konten mit der Rolle "Nutzer" verwalten
  const checkTarget = async (id: string) => {
    if (isAdmin) return null;
    const { data: t } = await admin.from("profiles").select("role").eq("id", id).maybeSingle();
    if (!t || t.role !== "nutzer") {
      return json({ error: "Die Einheitsführung darf nur Nutzer verwalten." }, 403);
    }
    return null;
  };

  try {
    if (action === "list") {
      const { data: list, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
      if (error) throw error;
      const { data: profiles } = await admin.from("profiles").select("id,name,role,unit_id");
      const byId = new Map((profiles ?? []).map((p: any) => [p.id, p]));
      let users = list.users.map((u: any) => ({
        id: u.id,
        email: u.email,
        name: byId.get(u.id)?.name ?? u.email,
        role: byId.get(u.id)?.role ?? "nutzer",
        unit_id: byId.get(u.id)?.unit_id ?? null,
        last_sign_in_at: u.last_sign_in_at,
        banned: !!u.banned_until && new Date(u.banned_until) > new Date(),
      }));
      if (!isAdmin) users = users.filter((u: any) => u.role === "nutzer");
      users.sort((a: any, b: any) => String(a.name).localeCompare(String(b.name), "de"));
      return json({ users });
    }

    if (action === "create") {
      const username = String(body.username ?? "").trim();
      const password = String(body.password ?? "");
      const role = isAdmin && ROLES.includes(body.role) ? body.role : "nutzer";
      const unitId = body.unit_id ? String(body.unit_id) : null;
      if (unitId) {
        const { data: un } = await admin.from("units").select("id").eq("id", unitId).maybeSingle();
        if (!un) return json({ error: "Unbekannte Einheit." }, 400);
      }
      if (!/^[^\s@.]+\.[^\s@.]+$/.test(username)) return json({ error: "Benutzername muss das Format Vorname.Nachname haben." }, 400);
      if (password.length < 8) return json({ error: "Das Passwort muss mindestens 8 Zeichen haben." }, 400);
      const { data, error } = await admin.auth.admin.createUser({
        email: `${username.toLowerCase()}@${USER_DOMAIN}`,
        password,
        email_confirm: true,
        user_metadata: { name: username },
      });
      if (error) throw error;
      const { error: pErr } = await admin.from("profiles").update({ name: username, role, unit_id: unitId }).eq("id", data.user.id);
      if (pErr) throw pErr;
      return json({ ok: true, id: data.user.id });
    }

    if (action === "set_unit") {
      const denied = await checkTarget(String(body.id));
      if (denied) return denied;
      const unitId = body.unit_id ? String(body.unit_id) : null;
      if (unitId) {
        const { data: un } = await admin.from("units").select("id").eq("id", unitId).maybeSingle();
        if (!un) return json({ error: "Unbekannte Einheit." }, 400);
      }
      const { error } = await admin.from("profiles").update({ unit_id: unitId }).eq("id", String(body.id));
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "set_password") {
      const denied = await checkTarget(String(body.id));
      if (denied) return denied;
      const password = String(body.password ?? "");
      if (password.length < 8) return json({ error: "Das Passwort muss mindestens 8 Zeichen haben." }, 400);
      const { error } = await admin.auth.admin.updateUserById(String(body.id), { password });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "ban") {
      if (body.id === user.id) return json({ error: "Du kannst dich nicht selbst sperren." }, 400);
      const denied = await checkTarget(String(body.id));
      if (denied) return denied;
      const { error } = await admin.auth.admin.updateUserById(String(body.id), {
        ban_duration: body.banned ? "876000h" : "none",
      });
      if (error) throw error;
      return json({ ok: true });
    }

    if (action === "delete") {
      if (body.id === user.id) return json({ error: "Du kannst dich nicht selbst löschen." }, 400);
      const denied = await checkTarget(String(body.id));
      if (denied) return denied;
      const { error } = await admin.auth.admin.deleteUser(String(body.id));
      if (error) {
        return json({ error: "Löschen nicht möglich – der Benutzer hat bereits Prüfungen durchgeführt. Bitte stattdessen sperren." }, 409);
      }
      return json({ ok: true });
    }

    return json({ error: "Unbekannte Aktion." }, 400);
  } catch (e: any) {
    return json({ error: e?.message ?? "Unbekannter Fehler." }, 400);
  }
});
